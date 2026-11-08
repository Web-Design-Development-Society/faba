-- Telling attendees about a new time or place (NOTIF-02). Design document sections 7.9 and 8.8. When
-- an activity's start, end or place changes, everyone going or maybe gets an activity_changed
-- notification with the before and after values, except the person who made the change. A run of
-- edits within 10 minutes makes one unread notification each. Description-only edits don't
-- notify. Private details (ACT-09) will notify too, and muting (NOTIF-08) will hold them back.

-- Making notifications as before (20261107120000_notifications.sql). A repeat keeps the first
-- one's `before`, so a run of edits reads from where it started.
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
  where r.id is not null
  on conflict on constraint notifications_recipient_id_dedupe_key_key do update
  set
    payload = excluded.payload || jsonb_strip_nulls(
      jsonb_build_object('before', notifications.payload -> 'before')
    ),
    actor_id = excluded.actor_id,
    created_at = now(),
    read_at = null;
  get diagnostics made = row_count;
  return made;
end;
$$;

-- Editing an activity as before (20261106230000_set_guests.sql), with the notification.
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
    'max_guests_per_rsvp'
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
    time_or_place_changed_at = case
      when (changed.starts_at, changed.ends_at, changed.location_name)
        is distinct from (saved.starts_at, saved.ends_at, saved.location_name)
      then now()
      else a.time_or_place_changed_at
    end,
    version = a.version + 1
  where a.id = saved.id;

  -- Everyone going or maybe, but the editor, hears about a new time or place (NOTIF-02), in this
  -- transaction. Within 10 minutes of the last change, they share its key, so a run of edits makes
  -- one notification each.
  if (changed.starts_at, changed.ends_at, changed.location_name)
    is distinct from (saved.starts_at, saved.ends_at, saved.location_name)
  then
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
      ),
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
