-- Welcoming guests (RSVP-06), when posting an activity and when editing it, with the most each RSVP
-- can bring. The columns and rsvp()'s rules are in 20261106220000_guests.sql.

-- Posting an activity as before (20261106170000_set_capacity.sql), welcoming guests or not.
DROP FUNCTION public.create_activity(
  text,
  text,
  timestamptz,
  text,
  text,
  timestamptz,
  text,
  uuid,
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
  max_guests_per_rsvp INTEGER DEFAULT 5
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
  INTEGER
)
TO authenticated;

-- Editing an activity as before (20261106170000_set_capacity.sql). The patch can change the guest
-- options too, until it starts. Members already bringing guests keep them if they're turned off
-- or the most is lowered, as with capacity.
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
end;
$$;
