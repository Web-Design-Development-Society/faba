-- RSVPs, and posting an activity with its organizer going (ACT-03; Iteration 1 tasks DB-4 and
-- DB-6). Design document sections 9.8 to 9.10, 10.3 and 10.5.

-- One member's response to one activity. Only functions write it: create_activity() now, and
-- rsvp() with RSVP-01.
CREATE TABLE public.rsvps (
  activity_id uuid NOT NULL REFERENCES public.activities (id)
    ON DELETE CASCADE,
  user_id uuid NOT NULL REFERENCES public.profiles (id)
    ON DELETE CASCADE,
  status text NOT NULL CHECK (status IN ('going', 'not_going')),
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now(),
  PRIMARY KEY (activity_id, user_id)
);

CREATE TRIGGER rsvps_set_updated_at
BEFORE UPDATE ON public.rsvps
FOR EACH ROW
EXECUTE FUNCTION private.set_updated_at();

ALTER TABLE public.rsvps ENABLE ROW LEVEL SECURITY;

-- A member's plans, and an activity's attendee list.
CREATE INDEX rsvps_user_idx ON public.rsvps (user_id, status);

CREATE INDEX rsvps_activity_idx ON public.rsvps (activity_id, status);

-- Section 9.8: members read their own RSVPs and who's going to the activities they can see, and
-- organizers read every RSVP to their own. Moderators get access with the moderation stories.
CREATE POLICY "Active members read their own RSVPs and who's going" ON public.rsvps
FOR SELECT
TO authenticated
USING (
  (SELECT private.is_active_member())
  AND (
    rsvps.user_id = (SELECT auth.uid())
    OR EXISTS (
      SELECT
      FROM public.activities AS a
      WHERE
        a.id = rsvps.activity_id
        AND (rsvps.status = 'going' OR a.organizer_id = (SELECT auth.uid()))
    )
  )
);

-- The daily limit counts a member's recent activities (section 9.10).
CREATE INDEX activities_organizer_created_idx ON public.activities (organizer_id, created_at);

-- Posts an activity and returns its id. The organizer is going, and going_count counts them. A
-- repeated idempotency key returns the activity it already made, so a double tap never posts twice
-- (section 9.9). Text is trimmed, and blank optional text is stored as NULL.
CREATE FUNCTION public.create_activity(
  title text,
  category_id text,
  starts_at timestamptz,
  location_name text,
  description text DEFAULT NULL,
  ends_at timestamptz DEFAULT NULL,
  cost_note text DEFAULT NULL,
  idempotency_key uuid DEFAULT NULL
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
    idempotency_key
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
    create_activity.idempotency_key
  )
  returning id into new_id;

  insert into public.rsvps (activity_id, user_id, status)
  values (new_id, auth.uid(), 'going');

  return new_id;
end;
$$;

GRANT EXECUTE
ON FUNCTION public.create_activity(text, text, timestamptz, text, text, timestamptz, text, uuid)
TO authenticated;
