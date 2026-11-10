-- Private details for attendees (ACT-09), and telling attendees when they change (NOTIF-02). Design
-- document sections 6.5, 9.8 and 10.3. An organizer can add details for attendees only, such as an
-- exact address, a gate code or a meeting link, of up to 500 characters. Only the organizer, members
-- going and moderators read them. Maybe and not-going members don't. They're kept in their own
-- table, so they're never in a feed, a search, or the activities table, and only create_activity()
-- and update_activity() write them. `activities.has_private_details` says there are some, so
-- everyone else can be told they're shared with attendees.
--
-- A change to them tells everyone going or maybe, as a new time or place does, but the notification
-- says only that they changed: maybe members can't read them, and a notification stays after its
-- reader stops going. They're deleted 30 days after the activity ends, and when its organizer
-- deletes their account, since they're often the organizer's address.

CREATE TABLE public.activity_private_details (
  activity_id uuid PRIMARY KEY REFERENCES public.activities (id)
    ON DELETE CASCADE,
  details text NOT NULL CHECK (char_length(details) BETWEEN 1 AND 500),
  updated_at timestamptz NOT NULL DEFAULT now()
);

ALTER TABLE public.activity_private_details ENABLE ROW LEVEL SECURITY;

-- Section 9.8. Reading the activity goes through its own policy, so a hidden activity's details
-- are only for its organizer and moderators.
CREATE POLICY "The organizer, members going and moderators read private details" ON public.activity_private_details
FOR SELECT
TO authenticated
USING (
  (SELECT private.is_active_member())
  AND EXISTS (
    SELECT
    FROM public.activities AS a
    WHERE
      a.id = activity_private_details.activity_id
      AND (
        a.organizer_id = (SELECT auth.uid())
        OR (SELECT private.is_moderator())
        OR EXISTS (
          SELECT
          FROM public.rsvps AS r
          WHERE r.activity_id = a.id AND r.user_id = (SELECT auth.uid()) AND r.status = 'going'
        )
      )
  )
);

-- Whether it has private details, which anyone who can see the activity can read.
ALTER TABLE public.activities
ADD COLUMN has_private_details BOOLEAN NOT NULL DEFAULT FALSE;

-- Saves an activity's private details, trimmed, and its has_private_details. Empty or null details
-- delete them. Returns whether they changed. Only create_activity() and update_activity() call it,
-- after checking the caller is the organizer.
CREATE FUNCTION private.set_private_details(activity_id uuid, details text)
RETURNS BOOLEAN
LANGUAGE plpgsql
SET search_path = ''
AS $$
declare
  saved text;
  wanted text := nullif(btrim(set_private_details.details, E' \t\r\n'), '');
begin
  if char_length(wanted) > 500 then
    raise exception 'INVALID_PRIVATE_DETAILS' using errcode = '22023';
  end if;

  select d.details into saved
  from public.activity_private_details as d
  where d.activity_id = set_private_details.activity_id;

  if wanted is not distinct from saved then
    return false;
  end if;

  if wanted is null then
    delete from public.activity_private_details as d
    where d.activity_id = set_private_details.activity_id;
  else
    insert into public.activity_private_details (activity_id, details)
    values (set_private_details.activity_id, wanted)
    on conflict on constraint activity_private_details_pkey do update
    set details = excluded.details, updated_at = now();
  end if;

  update public.activities as a
  set has_private_details = wanted is not null
  where a.id = set_private_details.activity_id;

  return true;
end;
$$;

REVOKE EXECUTE
ON FUNCTION private.set_private_details(uuid, text)
FROM PUBLIC, anon, authenticated, service_role;

-- Posting an activity as before (20261106230000_set_guests.sql), with its private details.
DROP FUNCTION public.create_activity(
  text,
  text,
  timestamptz,
  text,
  text,
  timestamptz,
  text,
  uuid,
  INTEGER,
  BOOLEAN,
  INTEGER
);

CREATE FUNCTION public.create_activity(
  title text,
  category_id text,
  starts_at timestamptz,
  location_name text,
  description text DEFAULT NULL,
  ends_at timestamptz DEFAULT NULL,
  cost_note text DEFAULT NULL,
  idempotency_key uuid DEFAULT NULL,
  capacity INTEGER DEFAULT NULL,
  guests_allowed BOOLEAN DEFAULT FALSE,
  max_guests_per_rsvp INTEGER DEFAULT 5,
  private_details text DEFAULT NULL
)
RETURNS uuid
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
declare
  new_id uuid;
begin
  if not private.is_active_member() then
    raise exception 'NOT_ACTIVE' using errcode = '42501';
  end if;

  -- One post at a time per member, so two taps can't both pass the checks below.
  perform pg_advisory_xact_lock(hashtextextended('create_activity ' || auth.uid(), 0));

  if create_activity.idempotency_key is not null then
    select a.id into new_id
    from public.activities as a
    where a.organizer_id = auth.uid() and a.idempotency_key = create_activity.idempotency_key;

    if found then
      return new_id;
    end if;
  end if;

  if not exists (
    select from public.categories as c
    where c.id = create_activity.category_id and c.is_active
  ) then
    raise exception 'INVALID_CATEGORY' using errcode = '22023';
  end if;

  if create_activity.starts_at <= now() then
    raise exception 'START_IN_PAST' using errcode = '22023';
  end if;

  if create_activity.starts_at > now() + interval '12 months' then
    raise exception 'START_TOO_FAR' using errcode = '22023';
  end if;

  if create_activity.ends_at <= create_activity.starts_at then
    raise exception 'END_BEFORE_START' using errcode = '22023';
  end if;

  if create_activity.capacity not between 1 and 500 then
    raise exception 'INVALID_CAPACITY' using errcode = '22023';
  end if;

  if create_activity.max_guests_per_rsvp not between 1 and 5 then
    raise exception 'INVALID_GUESTS' using errcode = '22023';
  end if;

  -- At most 10 in 24 hours (FR-ACT-5).
  if (
    select count(*)
    from public.activities as a
    where a.organizer_id = auth.uid() and a.created_at > now() - interval '24 hours'
  ) >= 10 then
    raise exception 'QUOTA_EXCEEDED' using errcode = 'P0001';
  end if;

  insert into public.activities (
    organizer_id,
    category_id,
    title,
    description,
    starts_at,
    ends_at,
    location_name,
    cost_note,
    going_count,
    idempotency_key,
    capacity,
    guests_allowed,
    max_guests_per_rsvp
  )
  values (
    auth.uid(),
    create_activity.category_id,
    trim(create_activity.title),
    nullif(trim(create_activity.description), ''),
    create_activity.starts_at,
    create_activity.ends_at,
    trim(create_activity.location_name),
    nullif(trim(create_activity.cost_note), ''),
    1,
    create_activity.idempotency_key,
    create_activity.capacity,
    coalesce(create_activity.guests_allowed, false),
    coalesce(create_activity.max_guests_per_rsvp, 5)
  )
  returning id into new_id;

  insert into public.rsvps (activity_id, user_id, status)
  values (new_id, auth.uid(), 'going');

  perform private.set_private_details(new_id, create_activity.private_details);

  return new_id;
end;
$$;

GRANT EXECUTE
ON FUNCTION public.create_activity(
  text,
  text,
  timestamptz,
  text,
  text,
  timestamptz,
  text,
  uuid,
  INTEGER,
  BOOLEAN,
  INTEGER,
  text
)
TO authenticated;

-- Editing an activity as before (20261107130000_activity_changed.sql). The patch can change its
-- private details too, even once it has started, as it can the description. A change to them tells
-- everyone going or maybe.
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
  if not found or saved.organizer_id is distinct from auth.uid() then
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
    version = a.version + 1
  where a.id = saved.id;

  -- Only when the patch has them, so leaving them out keeps them.
  if patch ? 'private_details' then
    details_changed := private.set_private_details(saved.id, patch ->> 'private_details');
  end if;

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

-- Making notifications as before (20261109140000_mute_activity.sql). A repeat in a run of edits also
-- keeps an earlier "details changed", so a later edit to only the time doesn't lose it.
CREATE OR REPLACE FUNCTION private.notify(
  recipients uuid[],
  type text,
  activity_id uuid,
  payload jsonb,
  dedupe_key text DEFAULT NULL
)
RETURNS INTEGER
LANGUAGE plpgsql
SET search_path = ''
AS $$
declare
  made integer;
begin
  insert into public.notifications (recipient_id, type, activity_id, actor_id, payload, dedupe_key)
  select distinct
    r.id,
    notify.type,
    notify.activity_id,
    auth.uid(),
    coalesce(notify.payload, '{}'),
    notify.dedupe_key
  from unnest(notify.recipients) as r (id)
  where
    r.id is not null
    and not (
      notify.type in ('activity_changed', 'organizer_update', 'new_attendees', 'reminder')
      and exists (
        select from public.activity_mutes as m
        where m.activity_id = notify.activity_id and m.user_id = r.id
      )
    )
  on conflict on constraint notifications_recipient_id_dedupe_key_key do update
  set
    payload = excluded.payload || jsonb_strip_nulls(
      jsonb_build_object(
        'before', notifications.payload -> 'before',
        'details_changed', notifications.payload -> 'details_changed'
      )
    ),
    actor_id = excluded.actor_id,
    created_at = now(),
    read_at = null;
  get diagnostics made = row_count;
  return made;
end;
$$;

-- Deleting old data as before (20261107120000_notifications.sql), and private details 30 days after
-- their activity ends (section 10.3). An activity without an end ends 3 hours after it starts, as
-- isOver() in src/lib/time.ts has it. Returns how many rows it deleted.
CREATE OR REPLACE FUNCTION private.purge_old_data()
RETURNS INTEGER
LANGUAGE sql
SET search_path = ''
AS $$
  WITH
    gone AS (
      DELETE FROM public.notifications
      WHERE created_at < now() - INTERVAL '90 days'
      RETURNING 1
    ),
    details AS (
      DELETE FROM public.activity_private_details AS d
      USING public.activities AS a
      WHERE
        a.id = d.activity_id
        AND coalesce(a.ends_at, a.starts_at + INTERVAL '3 hours') < now() - INTERVAL '30 days'
      RETURNING d.activity_id
    ),
    flags AS (
      UPDATE public.activities AS a
      SET has_private_details = FALSE
      FROM details
      WHERE a.id = details.activity_id
      RETURNING 1
    )
  SELECT ((SELECT count(*) FROM gone) + (SELECT count(*) FROM details))::INTEGER;
$$;

-- Deleting an account as before (20261107140000_activity_cancelled.sql), and the private details of
-- every activity they organize, which are often their address.
CREATE OR REPLACE FUNCTION public.delete_my_account()
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
declare
  cancelled integer := 0;
  removed integer;
  gone record;
begin
  if not exists (select from public.profiles as p where p.id = auth.uid()) then
    raise exception 'ACCOUNT_NOT_FOUND' using errcode = 'P0002';
  end if;

  -- Activities they organize that haven't started. Their attendees still find them, cancelled, and
  -- hear about it (NOTIF-03).
  for gone in
    update public.activities as a
    set status = 'cancelled', cancel_reason = 'Its organizer left FABA.', cancelled_at = now()
    where a.organizer_id = auth.uid() and a.status = 'published' and a.starts_at > now()
    returning a.id, a.title, a.starts_at
  loop
    cancelled := cancelled + 1;
    perform private.notify_attendees(
      gone.id,
      'activity_cancelled',
      jsonb_build_object(
        'title', gone.title,
        'starts_at', gone.starts_at,
        'reason', 'Its organizer left FABA.'
      )
    );
  end loop;

  -- The private details of every activity they organize, which are often their address.
  with removed_details as (
    delete from public.activity_private_details as d
    using public.activities as a
    where a.id = d.activity_id and a.organizer_id = auth.uid()
    returning d.activity_id
  )
  update public.activities as a
  set has_private_details = false
  from removed_details as d
  where a.id = d.activity_id;

  -- Their RSVPs, with the going and maybe counts and the guests that rsvp() keeps (ADR-008).
  update public.activities as a
  set
    going_count = a.going_count - (r.status = 'going')::integer,
    maybe_count = a.maybe_count - (r.status = 'maybe')::integer,
    guest_total = a.guest_total - r.guest_count
  from public.rsvps as r
  where r.activity_id = a.id and r.user_id = auth.uid() and r.status in ('going', 'maybe');

  delete from public.rsvps as r
  where r.user_id = auth.uid();
  get diagnostics removed = row_count;

  perform private.audit(
    'delete_account',
    'profile',
    auth.uid(),
    NULL,
    jsonb_build_object('activities_cancelled', cancelled, 'rsvps_removed', removed)
  );
end;
$$;
