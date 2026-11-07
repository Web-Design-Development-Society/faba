-- Bringing guests (RSVP-06). Design document sections 7.8 and 10.3, and FR-ACT-7 and FR-RSVP-5. An
-- organizer can welcome guests, up to a number per RSVP, and a member going says how many they're
-- bringing. Guests are a count only: no names or details are collected. They count toward the
-- capacity (RSVP-04). 20261106230000_set_guests.sql lets organizers welcome them.

ALTER TABLE public.activities
ADD COLUMN guests_allowed BOOLEAN NOT NULL DEFAULT FALSE,
ADD COLUMN max_guests_per_rsvp INTEGER NOT NULL DEFAULT 5 CHECK (
  max_guests_per_rsvp BETWEEN 1 AND 5
);

-- Kept at 0 unless the member is going.
ALTER TABLE public.rsvps
ADD COLUMN guest_count INTEGER NOT NULL DEFAULT 0 CHECK (guest_count BETWEEN 0 AND 5);

-- Saying "I'm in" as before (20261106200000_maybe.sql), with a number of guests. Without one, a
-- member going keeps the guests they had. guest_total changes only here, like the other counts
-- (ADR-008).
DROP FUNCTION public.rsvp(uuid, text);

CREATE FUNCTION public.rsvp(activity_id uuid, status text, guests INTEGER DEFAULT NULL)
RETURNS INTEGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
declare
  activity public.activities;
  previous text;
  had integer;
  wanted integer;
begin
  if not private.is_active_member() then
    raise exception 'NOT_ACTIVE' using errcode = '42501';
  end if;

  if rsvp.status is null or rsvp.status not in ('going', 'maybe', 'not_going') then
    raise exception 'INVALID_STATUS' using errcode = '22023';
  end if;

  -- Locked, so RSVPs to one activity count one at a time.
  select * into activity from public.activities as a where a.id = rsvp.activity_id for update;

  if not found then
    raise exception 'ACTIVITY_NOT_FOUND' using errcode = 'P0002';
  end if;

  -- The organizer went when they posted it, and stays going (RSVP-02).
  if activity.organizer_id = auth.uid() then
    raise exception 'ORGANIZER_GOING' using errcode = '22023';
  end if;

  -- Only its organizer can see a hidden activity.
  if activity.hidden_at is not null then
    raise exception 'ACTIVITY_NOT_FOUND' using errcode = 'P0002';
  end if;

  if activity.status = 'cancelled' then
    raise exception 'ACTIVITY_CANCELLED' using errcode = '22023';
  end if;

  if coalesce(activity.ends_at, activity.starts_at + interval '3 hours') <= now() then
    raise exception 'ACTIVITY_OVER' using errcode = '22023';
  end if;

  -- Guests come only when the organizer welcomes them, up to their number.
  if rsvp.guests < 0 or rsvp.guests > 0 and (
    not activity.guests_allowed or rsvp.guests > activity.max_guests_per_rsvp
  ) then
    raise exception 'INVALID_GUESTS' using errcode = '22023';
  end if;

  select r.status, r.guest_count into previous, had
  from public.rsvps as r
  where r.activity_id = rsvp.activity_id and r.user_id = auth.uid();
  had := coalesce(had, 0);
  wanted := case
    when rsvp.status != 'going' then 0
    else coalesce(rsvp.guests, case when previous = 'going' then had else 0 end)
  end;

  -- Full, once going and guests reach the capacity. The row is locked above, so two members can't
  -- both take the last spot. Someone going keeps their spot and guests, or brings fewer, even after
  -- the capacity is lowered.
  if rsvp.status = 'going'
    and (previous is distinct from 'going' or wanted > had)
    and activity.going_count + activity.guest_total
      - (case when previous = 'going' then 1 + had else 0 end)
      + 1 + wanted > activity.capacity
  then
    raise exception 'ACTIVITY_FULL' using errcode = '22023';
  end if;

  if previous is distinct from rsvp.status or wanted != had then
    insert into public.rsvps (activity_id, user_id, status, guest_count)
    values (rsvp.activity_id, auth.uid(), rsvp.status, wanted)
    on conflict on constraint rsvps_pkey do update
    set status = excluded.status, guest_count = excluded.guest_count;

    update public.activities as a
    set
      going_count = a.going_count
        + (case when rsvp.status = 'going' then 1 else 0 end)
        - (case when previous = 'going' then 1 else 0 end),
      maybe_count = a.maybe_count
        + (case when rsvp.status = 'maybe' then 1 else 0 end)
        - (case when previous = 'maybe' then 1 else 0 end),
      guest_total = a.guest_total + wanted - (case when previous = 'going' then had else 0 end)
    where a.id = rsvp.activity_id
    returning a.going_count into activity.going_count;
  end if;

  return activity.going_count;
end;
$$;

GRANT EXECUTE ON FUNCTION public.rsvp(uuid, text, INTEGER) TO authenticated;
