-- Post again (ACT-07). Design document sections 7.7 and 10.3. An organizer can copy one of their
-- past or cancelled activities into a new one. The new activity keeps only `copied_from_id`, for
-- analytics (section 6.5), and nothing else links them. It's kept only when the original is the
-- organizer's own, and it's cleared when the original goes.

ALTER TABLE public.activities
ADD COLUMN copied_from_id uuid REFERENCES public.activities (id)
  ON DELETE SET NULL;

CREATE INDEX activities_copied_from_idx ON public.activities (copied_from_id);

-- Posting as before (20261110140000_private_details.sql), with the activity it was copied from.
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
  INTEGER,
  text
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
  private_details text DEFAULT NULL,
  copied_from_id uuid DEFAULT NULL
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
    max_guests_per_rsvp,
    copied_from_id
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
    coalesce(create_activity.max_guests_per_rsvp, 5),
    -- Kept only when it's one of theirs, so it can't point at anyone else's.
    (
      select a.id
      from public.activities as a
      where a.id = create_activity.copied_from_id and a.organizer_id = auth.uid()
    )
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
  text,
  uuid
)
TO authenticated;
