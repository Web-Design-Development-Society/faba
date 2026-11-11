-- Co-organizers (ACT-10). An organizer can add up to 3 co-organizers to an activity. They get the
-- same rights as the organizer, except removing the organizer. The helper private.is_activity_organizer()
-- is the one check that the write paths use, so the existing policies don't change. The organizer
-- stays on the activity row; co-organizers live in public.activity_co_organizers.

CREATE TABLE public.activity_co_organizers (
  activity_id uuid NOT NULL REFERENCES public.activities (id)
    ON DELETE CASCADE,
  user_id uuid NOT NULL REFERENCES public.profiles (id)
    ON DELETE CASCADE,
  added_by uuid REFERENCES public.profiles (id)
    ON DELETE SET NULL,
  added_at timestamptz NOT NULL DEFAULT now(),
  PRIMARY KEY (activity_id, user_id)
);

CREATE INDEX activity_co_organizers_user_idx ON public.activity_co_organizers (user_id);

ALTER TABLE public.activity_co_organizers ENABLE ROW LEVEL SECURITY;

-- Active members see co-organizers of the activities they can already see. Writes go through the
-- functions below only.
CREATE POLICY activity_co_organizers_select ON public.activity_co_organizers
FOR SELECT
TO authenticated
USING (
  private.is_active_member()
  AND EXISTS (SELECT FROM public.activities AS a WHERE a.id = activity_co_organizers.activity_id)
);

GRANT SELECT ON public.activity_co_organizers TO authenticated;

-- True when the caller is the activity's organizer or one of its co-organizers.
CREATE FUNCTION private.is_activity_organizer(activity_id uuid)
RETURNS BOOLEAN
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = ''
AS $$
  SELECT EXISTS (
    SELECT
    FROM public.activities AS a
    WHERE a.id = is_activity_organizer.activity_id AND a.organizer_id = (SELECT auth.uid())
  )
  OR EXISTS (
    SELECT
    FROM public.activity_co_organizers AS c
    WHERE c.activity_id = is_activity_organizer.activity_id AND c.user_id = (SELECT auth.uid())
  );
$$;

GRANT EXECUTE ON FUNCTION private.is_activity_organizer(uuid) TO authenticated;

-- Adds `user_id`, an active member, as a co-organizer of `activity_id` (ACT-10). Only the organizer
-- or a co-organizer can, and an activity has up to 3. Adding someone who already is one changes
-- nothing.
CREATE FUNCTION public.add_co_organizer(activity_id uuid, user_id uuid)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
declare
  activity public.activities;
  current_count integer;
begin
  if not private.is_active_member() then
    raise exception 'NOT_ACTIVE' using errcode = '42501';
  end if;

  -- Locks the activity, so two adds can't both take the last of the 3 places.
  select * into activity
  from public.activities as a
  where a.id = add_co_organizer.activity_id
  for update;

  if not found or not private.is_activity_organizer(activity.id) then
    raise exception 'NOT_ORGANIZER' using errcode = '42501';
  end if;

  if add_co_organizer.user_id = activity.organizer_id then
    return;
  end if;

  if not exists (
    select from public.profiles as p
    where p.id = add_co_organizer.user_id and p.status = 'active'
  ) then
    raise exception 'MEMBER_NOT_FOUND' using errcode = 'P0002';
  end if;

  if exists (
    select from public.activity_co_organizers as c
    where c.activity_id = activity.id and c.user_id = add_co_organizer.user_id
  ) then
    return;
  end if;

  select count(*) into current_count
  from public.activity_co_organizers as c
  where c.activity_id = activity.id;

  if current_count >= 3 then
    raise exception 'TOO_MANY_CO_ORGANIZERS' using errcode = '22023';
  end if;

  insert into public.activity_co_organizers (activity_id, user_id, added_by)
  values (activity.id, add_co_organizer.user_id, (select auth.uid()));
end;
$$;

GRANT EXECUTE ON FUNCTION public.add_co_organizer(uuid, uuid) TO authenticated;

-- Removes co-organizer `user_id` from `activity_id`. Only the organizer or a co-organizer can. The
-- organizer can't be removed this way, and removing someone who isn't one changes nothing.
CREATE FUNCTION public.remove_co_organizer(activity_id uuid, user_id uuid)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
declare
  activity public.activities;
begin
  if not private.is_active_member() then
    raise exception 'NOT_ACTIVE' using errcode = '42501';
  end if;

  select * into activity
  from public.activities as a
  where a.id = remove_co_organizer.activity_id
  for update;

  if not found or not private.is_activity_organizer(activity.id) then
    raise exception 'NOT_ORGANIZER' using errcode = '42501';
  end if;

  delete from public.activity_co_organizers as c
  where c.activity_id = activity.id and c.user_id = remove_co_organizer.user_id;
end;
$$;

GRANT EXECUTE ON FUNCTION public.remove_co_organizer(uuid, uuid) TO authenticated;

-- The write paths now accept co-organizers as well as the organizer (ACT-10). Each is its latest
-- definition, with only its organizer check changed.

CREATE OR REPLACE FUNCTION public.update_activity(
  activity_id uuid,
  patch jsonb,
  expected_version INTEGER
)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
declare
  saved public.activities;
  changed public.activities;
  edited BOOLEAN;
  moved BOOLEAN;
  details_changed BOOLEAN := false;
begin
  if not private.is_active_member() then
    raise exception 'NOT_ACTIVE' using errcode = '42501';
  end if;

  if patch - array[
    'title',
    'category_id',
    'starts_at',
    'ends_at',
    'location_name',
    'description',
    'cost_note',
    'capacity',
    'guests_allowed',
    'max_guests_per_rsvp',
    'private_details'
  ] != '{}'::jsonb then
    raise exception 'INVALID_FIELD' using errcode = '22023';
  end if;

  select * into saved
  from public.activities as a
  where a.id = update_activity.activity_id
  for update;

  -- The same for an activity that doesn't exist, so nobody learns which ones do.
  if not found or not private.is_activity_organizer(saved.id) then
    raise exception 'NOT_ORGANIZER' using errcode = '42501';
  end if;

  if saved.version != update_activity.expected_version then
    raise exception 'STALE_EDIT' using errcode = '40001';
  end if;

  changed := jsonb_populate_record(saved, patch);
  changed.title := trim(changed.title);
  changed.description := nullif(trim(changed.description), '');
  changed.location_name := trim(changed.location_name);
  changed.cost_note := nullif(trim(changed.cost_note), '');

  if saved.starts_at <= now() then
    if (
      changed.title,
      changed.category_id,
      changed.starts_at,
      changed.ends_at,
      changed.location_name,
      changed.cost_note,
      changed.capacity,
      changed.guests_allowed,
      changed.max_guests_per_rsvp
    ) is distinct from (
      saved.title,
      saved.category_id,
      saved.starts_at,
      saved.ends_at,
      saved.location_name,
      saved.cost_note,
      saved.capacity,
      saved.guests_allowed,
      saved.max_guests_per_rsvp
    ) then
      raise exception 'ACTIVITY_STARTED' using errcode = '22023';
    end if;
  else
    -- An activity keeps a category that's no longer offered until it's changed.
    if changed.category_id != saved.category_id and not exists (
      select from public.categories as c
      where c.id = changed.category_id and c.is_active
    ) then
      raise exception 'INVALID_CATEGORY' using errcode = '22023';
    end if;

    if changed.starts_at <= now() then
      raise exception 'START_IN_PAST' using errcode = '22023';
    end if;

    if changed.starts_at > now() + interval '12 months' then
      raise exception 'START_TOO_FAR' using errcode = '22023';
    end if;

    if changed.ends_at <= changed.starts_at then
      raise exception 'END_BEFORE_START' using errcode = '22023';
    end if;

    if changed.capacity not between 1 and 500 then
      raise exception 'INVALID_CAPACITY' using errcode = '22023';
    end if;

    if changed.guests_allowed is null or changed.max_guests_per_rsvp not between 1 and 5 then
      raise exception 'INVALID_GUESTS' using errcode = '22023';
    end if;
  end if;

  moved := (changed.starts_at, changed.ends_at, changed.location_name)
    is distinct from (saved.starts_at, saved.ends_at, saved.location_name);

  edited := moved or (
    changed.title,
    changed.category_id,
    changed.description,
    changed.cost_note,
    changed.capacity,
    changed.guests_allowed,
    changed.max_guests_per_rsvp
  ) is distinct from (
    saved.title,
    saved.category_id,
    saved.description,
    saved.cost_note,
    saved.capacity,
    saved.guests_allowed,
    saved.max_guests_per_rsvp
  );

  -- Only when the patch has them, so leaving them out keeps them.
  if patch ? 'private_details' then
    details_changed := private.set_private_details(saved.id, patch ->> 'private_details');
  end if;

  update public.activities as a
  set
    title = changed.title,
    category_id = changed.category_id,
    description = changed.description,
    starts_at = changed.starts_at,
    ends_at = changed.ends_at,
    location_name = changed.location_name,
    cost_note = changed.cost_note,
    capacity = changed.capacity,
    guests_allowed = changed.guests_allowed,
    max_guests_per_rsvp = changed.max_guests_per_rsvp,
    time_or_place_changed_at = case when moved then now() else a.time_or_place_changed_at end,
    -- A save that changes nothing leaves a date in its series (REC-02).
    series_detached = a.series_detached
      or a.series_id is not null and (edited or details_changed),
    version = a.version + 1
  where a.id = saved.id;

  -- Everyone going or maybe, but the editor, hears about a new time, place or private details
  -- (NOTIF-02), in this transaction. Within 10 minutes of the last change, they share its key, so a
  -- run of edits makes one notification each. It says the details changed, but not what they are.
  if moved or details_changed then
    perform private.notify(
      array(
        select r.user_id
        from public.rsvps as r
        join public.profiles as p on p.id = r.user_id
        where
          r.activity_id = saved.id
          and r.status in ('going', 'maybe')
          and r.user_id != auth.uid()
          and p.status = 'active'
      ),
      'activity_changed',
      saved.id,
      jsonb_build_object(
        'title', changed.title,
        'before', jsonb_build_object(
          'starts_at', saved.starts_at,
          'ends_at', saved.ends_at,
          'location_name', saved.location_name
        ),
        'after', jsonb_build_object(
          'starts_at', changed.starts_at,
          'ends_at', changed.ends_at,
          'location_name', changed.location_name
        )
      ) || case when details_changed then '{"details_changed": true}'::jsonb else '{}' end,
      coalesce(
        (
          select n.dedupe_key
          from public.notifications as n
          where
            n.activity_id = saved.id
            and n.type = 'activity_changed'
            and n.created_at > now() - interval '10 minutes'
          order by n.created_at desc
          limit 1
        ),
        'activity_changed:' || saved.id || ':' || gen_random_uuid()
      )
    );
  end if;
end;
$$;

CREATE OR REPLACE FUNCTION public.set_activity_tags(activity_id uuid, tag_ids text[])
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
declare
  activity public.activities;
  wanted text[] := array(select distinct unnest(coalesce(set_activity_tags.tag_ids, '{}')));
  had text[];
begin
  if not private.is_active_member() then
    raise exception 'NOT_ACTIVE' using errcode = '42501';
  end if;

  select * into activity
  from public.activities as a
  where a.id = set_activity_tags.activity_id
  for update;

  -- The same for an activity that doesn't exist, so nobody learns which ones do.
  if not found or not private.is_activity_organizer(activity.id) then
    raise exception 'NOT_ORGANIZER' using errcode = '42501';
  end if;

  had := array(
    select t.tag_id from public.activity_tags as t where t.activity_id = activity.id
  );

  if wanted <@ had and had <@ wanted then
    return;
  end if;

  if activity.starts_at <= now() then
    raise exception 'ACTIVITY_STARTED' using errcode = '22023';
  end if;

  if cardinality(wanted) > 3 then
    raise exception 'TOO_MANY_TAGS' using errcode = '22023';
  end if;

  if exists (
    select from unnest(wanted) as w (id)
    where w.id <> all(had) and not exists (
      select from public.tags as g where g.id = w.id and g.is_active
    )
  ) then
    raise exception 'INVALID_TAG' using errcode = '22023';
  end if;

  delete from public.activity_tags as t
  where t.activity_id = activity.id and t.tag_id <> all(wanted);

  insert into public.activity_tags (activity_id, tag_id)
  select activity.id, w.id
  from unnest(wanted) as w (id)
  on conflict do nothing;

  update public.activities as a
  set series_detached = true
  where a.id = activity.id and a.series_id is not null and not a.series_detached;
end;
$$;

CREATE OR REPLACE FUNCTION public.update_series(
  activity_id uuid,
  patch jsonb,
  expected_version INTEGER,
  tag_ids text[] DEFAULT NULL
)
RETURNS INTEGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
declare
  saved public.activities;
  changed public.activities;
  s public.activity_series;
  wanted text[] := array(select distinct unnest(coalesce(update_series.tag_ids, '{}')));
  details text := nullif(btrim(patch ->> 'private_details', E' \t\r\n'), '');
  shift INTEGER;
  new_time TIME;
  new_duration INTERVAL;
  o public.activities;
  o_starts timestamptz;
  o_ends timestamptz;
  o_moved BOOLEAN;
  o_details BOOLEAN;
  recipients uuid[];
  told uuid[] := '{}';
  made INTEGER := 0;
begin
  if not private.is_active_member() then
    raise exception 'NOT_ACTIVE' using errcode = '42501';
  end if;

  if patch - array[
    'title',
    'category_id',
    'starts_at',
    'ends_at',
    'location_name',
    'description',
    'cost_note',
    'capacity',
    'guests_allowed',
    'max_guests_per_rsvp',
    'private_details'
  ] != '{}'::jsonb then
    raise exception 'INVALID_FIELD' using errcode = '22023';
  end if;

  -- The series first, as generate_occurrences() locks it, so two saves can't wait on each other.
  select x.* into s
  from public.activity_series as x
  join public.activities as a on a.series_id = x.id
  where a.id = update_series.activity_id
  for update of x;

  select * into saved
  from public.activities as a
  where a.id = update_series.activity_id
  for update;

  -- The same for an activity that doesn't exist, so nobody learns which ones do.
  if saved.id is null or not private.is_activity_organizer(saved.id) then
    raise exception 'NOT_ORGANIZER' using errcode = '42501';
  end if;

  -- A date that was handed to a new host isn't the series' to change either.
  if s.id is null
    or saved.series_id is distinct from s.id
    or saved.series_detached
    or not private.is_activity_organizer(saved.id)
  then
    raise exception 'NOT_IN_SERIES' using errcode = '22023';
  end if;

  if saved.version != update_series.expected_version then
    raise exception 'STALE_EDIT' using errcode = '40001';
  end if;

  if saved.starts_at <= now() then
    raise exception 'ACTIVITY_STARTED' using errcode = '22023';
  end if;

  changed := jsonb_populate_record(saved, patch);
  changed.title := trim(changed.title);
  changed.description := nullif(trim(changed.description), '');
  changed.location_name := trim(changed.location_name);
  changed.cost_note := nullif(trim(changed.cost_note), '');

  -- A series keeps a category or a tag that's no longer offered until it's changed.
  if changed.category_id != saved.category_id and not exists (
    select from public.categories as c
    where c.id = changed.category_id and c.is_active
  ) then
    raise exception 'INVALID_CATEGORY' using errcode = '22023';
  end if;

  if changed.starts_at <= now() then
    raise exception 'START_IN_PAST' using errcode = '22023';
  end if;

  if changed.starts_at > now() + interval '12 months' then
    raise exception 'START_TOO_FAR' using errcode = '22023';
  end if;

  if changed.ends_at <= changed.starts_at then
    raise exception 'END_BEFORE_START' using errcode = '22023';
  end if;

  if changed.capacity not between 1 and 500 then
    raise exception 'INVALID_CAPACITY' using errcode = '22023';
  end if;

  if changed.guests_allowed is null or changed.max_guests_per_rsvp not between 1 and 5 then
    raise exception 'INVALID_GUESTS' using errcode = '22023';
  end if;

  if cardinality(wanted) > 3 then
    raise exception 'TOO_MANY_TAGS' using errcode = '22023';
  end if;

  if exists (
    select from unnest(wanted) as w (id)
    where w.id <> all(s.tag_ids) and not exists (
      select from public.tags as g where g.id = w.id and g.is_active
    )
  ) then
    raise exception 'INVALID_TAG' using errcode = '22023';
  end if;

  if char_length(details) > 500 then
    raise exception 'INVALID_PRIVATE_DETAILS' using errcode = '22023';
  end if;

  -- On the series' calendar, so 7:00 PM stays 7:00 PM when the clocks change.
  shift := (changed.starts_at at time zone s.timezone)::date
    - (saved.starts_at at time zone s.timezone)::date;
  new_time := (changed.starts_at at time zone s.timezone)::time;
  new_duration := changed.ends_at - changed.starts_at;

  -- A monthly series is on a day of the month, which moving by days wouldn't keep.
  if shift != 0 and s.freq in ('monthly_date', 'monthly_nth') then
    raise exception 'MONTHLY_DATE_FIXED' using errcode = '22023';
  end if;

  -- The series moves with its dates, so the ones made later follow.
  update public.activity_series as x
  set
    category_id = changed.category_id,
    title = changed.title,
    description = changed.description,
    location_name = changed.location_name,
    cost_note = changed.cost_note,
    capacity = changed.capacity,
    guests_allowed = changed.guests_allowed,
    max_guests_per_rsvp = changed.max_guests_per_rsvp,
    tag_ids = wanted,
    start_time = new_time,
    duration = new_duration,
    start_date = x.start_date + shift,
    -- A series that rolls on still does. least() would skip the null and give it a last date.
    until_date = case
      when x.until_date is not null
      then least(x.until_date + shift, (x.start_date + shift + interval '12 months')::date)
    end,
    generated_through = x.generated_through + shift
  where x.id = s.id;

  -- Only when the patch has them, so leaving them out keeps them.
  if patch ? 'private_details' then
    if details is null then
      delete from private.series_private_details as p
      where p.series_id = s.id;
    else
      insert into private.series_private_details (series_id, details)
      values (s.id, details)
      on conflict on constraint series_private_details_pkey do update
      set details = excluded.details;
    end if;
  end if;

  for o in
    select a.*
    from public.activities as a
    where
      a.series_id = s.id
      and not a.series_detached
      and private.is_activity_organizer(a.id)
      and a.starts_at >= saved.starts_at
    order by a.starts_at
    for update
  loop
    o_starts := ((o.starts_at at time zone s.timezone)::date + shift + new_time)
      at time zone s.timezone;
    o_ends := o_starts + new_duration;
    o_moved := (o_starts, o_ends, changed.location_name)
      is distinct from (o.starts_at, o.ends_at, o.location_name);

    update public.activities as a
    set
      title = changed.title,
      category_id = changed.category_id,
      description = changed.description,
      starts_at = o_starts,
      ends_at = o_ends,
      location_name = changed.location_name,
      cost_note = changed.cost_note,
      capacity = changed.capacity,
      guests_allowed = changed.guests_allowed,
      max_guests_per_rsvp = changed.max_guests_per_rsvp,
      time_or_place_changed_at = case when o_moved then now() else a.time_or_place_changed_at end,
      version = a.version + 1
    where a.id = o.id;

    delete from public.activity_tags as t
    where t.activity_id = o.id and t.tag_id <> all(wanted);

    insert into public.activity_tags (activity_id, tag_id)
    select o.id, w.id
    from unnest(wanted) as w (id)
    on conflict do nothing;

    o_details := patch ? 'private_details' and private.set_private_details(o.id, details);

    -- Everyone going or maybe hears once, on the first changed date they're going to that they
    -- haven't muted (NOTIF-02, NOTIF-08), and it says the later dates changed too.
    if (o_moved or o_details) and o.status = 'published' then
      recipients := array(
        select r.user_id
        from public.rsvps as r
        join public.profiles as p on p.id = r.user_id
        where
          r.activity_id = o.id
          and r.status in ('going', 'maybe')
          and r.user_id != auth.uid()
          and r.user_id != all(told)
          and p.status = 'active'
          and not exists (
            select from public.activity_mutes as m
            where m.activity_id = o.id and m.user_id = r.user_id
          )
      );

      if cardinality(recipients) > 0 then
        perform private.notify(
          recipients,
          'activity_changed',
          o.id,
          jsonb_build_object(
            'title', changed.title,
            'series', true,
            'before', jsonb_build_object(
              'starts_at', o.starts_at,
              'ends_at', o.ends_at,
              'location_name', o.location_name
            ),
            'after', jsonb_build_object(
              'starts_at', o_starts,
              'ends_at', o_ends,
              'location_name', changed.location_name
            )
          ) || case when o_details then '{"details_changed": true}'::jsonb else '{}' end,
          coalesce(
            (
              select n.dedupe_key
              from public.notifications as n
              where
                n.activity_id = o.id
                and n.type = 'activity_changed'
                and n.created_at > now() - interval '10 minutes'
              order by n.created_at desc
              limit 1
            ),
            'activity_changed:' || o.id || ':' || gen_random_uuid()
          )
        );
        told := told || recipients;
      end if;
    end if;

    made := made + 1;
  end loop;

  return made;
end;
$$;

CREATE OR REPLACE FUNCTION public.cancel_activity(activity_id uuid, reason text DEFAULT NULL)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
declare
  activity public.activities;
begin
  if not private.is_active_member() then
    raise exception 'NOT_ACTIVE' using errcode = '42501';
  end if;

  select * into activity
  from public.activities as a
  where a.id = cancel_activity.activity_id
  for update;

  -- The same for an activity that doesn't exist, so nobody learns which ones do.
  if not found or not private.is_activity_organizer(activity.id) then
    raise exception 'NOT_ORGANIZER' using errcode = '42501';
  end if;

  if activity.status = 'cancelled' then
    return;
  end if;

  update public.activities as a
  set
    status = 'cancelled',
    cancel_reason = nullif(trim(cancel_activity.reason), ''),
    cancelled_at = now()
  where a.id = activity.id;

  perform private.notify_attendees(
    activity.id,
    'activity_cancelled',
    jsonb_build_object(
      'title', activity.title,
      'starts_at', activity.starts_at,
      'reason', nullif(trim(cancel_activity.reason), '')
    )
  );
end;
$$;

CREATE OR REPLACE FUNCTION public.restore_activity(activity_id uuid)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
declare
  activity public.activities;
begin
  if not private.is_active_member() then
    raise exception 'NOT_ACTIVE' using errcode = '42501';
  end if;

  select * into activity
  from public.activities as a
  where a.id = restore_activity.activity_id
  for update;

  if not found or not private.is_activity_organizer(activity.id) then
    raise exception 'NOT_ORGANIZER' using errcode = '42501';
  end if;

  if activity.status = 'published' then
    return;
  end if;

  if activity.starts_at <= now() then
    raise exception 'RESTORE_TOO_LATE' using errcode = '22023';
  end if;

  update public.activities as a
  set status = 'published', cancel_reason = null, cancelled_at = null
  where a.id = activity.id;

  perform private.notify_attendees(
    activity.id,
    'activity_restored',
    jsonb_build_object('title', activity.title, 'starts_at', activity.starts_at)
  );
end;
$$;

CREATE OR REPLACE FUNCTION public.post_activity_update(
  activity_id uuid,
  body text,
  idempotency_key uuid DEFAULT NULL
)
RETURNS uuid
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
declare
  activity public.activities;
  posted text := btrim(post_activity_update.body, E' \t\r\n');
  new_id uuid;
begin
  if not private.is_active_member() then
    raise exception 'NOT_ACTIVE' using errcode = '42501';
  end if;

  -- Locked, so updates to one activity count one at a time.
  select * into activity
  from public.activities as a
  where a.id = post_activity_update.activity_id
  for update;

  -- The same for an activity that doesn't exist, so nobody learns which ones do.
  if not found or not private.is_activity_organizer(activity.id) then
    raise exception 'NOT_ORGANIZER' using errcode = '42501';
  end if;

  if post_activity_update.idempotency_key is not null then
    select u.id into new_id
    from public.activity_updates as u
    where u.author_id = auth.uid() and u.idempotency_key = post_activity_update.idempotency_key;

    if found then
      return new_id;
    end if;
  end if;

  -- Nobody but its organizer can see a hidden activity, so it tells nobody anything.
  if activity.hidden_at is not null then
    raise exception 'ACTIVITY_HIDDEN' using errcode = '22023';
  end if;

  if posted is null or char_length(posted) not between 1 and 500 then
    raise exception 'INVALID_BODY' using errcode = '22023';
  end if;

  -- At most 5 to an activity in 24 hours, hidden ones included (NOTIF-04).
  if (
    select count(*)
    from public.activity_updates as u
    where u.activity_id = activity.id and u.created_at > now() - interval '24 hours'
  ) >= 5 then
    raise exception 'UPDATE_QUOTA_EXCEEDED' using errcode = 'P0001';
  end if;

  insert into public.activity_updates (activity_id, author_id, body, idempotency_key)
  values (activity.id, auth.uid(), posted, post_activity_update.idempotency_key)
  returning id into new_id;

  perform private.notify_attendees(
    activity.id,
    'organizer_update',
    jsonb_build_object('update_id', new_id, 'title', activity.title, 'starts_at', activity.starts_at)
  );

  return new_id;
end;
$$;
