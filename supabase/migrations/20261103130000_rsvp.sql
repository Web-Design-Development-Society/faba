-- Saying "I'm in" (RSVP-01). Design document sections 9.9, 10.3 and 10.5.

-- Sets the signed-in member's RSVP to an activity, and returns the activity's going count. It's
-- the only way members write RSVPs, so later capacity and waitlist rules go here, and going_count
-- changes only here (ADR-008). Undo sets not_going, which nobody else sees or counts.
-- An activity takes RSVPs until it's over: when it ends, or 3 hours after it starts without an end
-- time, as long as the feed shows it.
CREATE FUNCTION public.rsvp(activity_id uuid, status text)
RETURNS INTEGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
declare
  activity public.activities;
  previous text;
begin
  if not private.is_active_member() then
    raise exception 'NOT_ACTIVE' using errcode = '42501';
  end if;

  if rsvp.status is null or rsvp.status not in ('going', 'not_going') then
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

  select r.status into previous
  from public.rsvps as r
  where r.activity_id = rsvp.activity_id and r.user_id = auth.uid();

  if previous is distinct from rsvp.status then
    insert into public.rsvps (activity_id, user_id, status)
    values (rsvp.activity_id, auth.uid(), rsvp.status)
    on conflict on constraint rsvps_pkey do update set status = excluded.status;

    update public.activities as a
    set going_count = a.going_count
      + (case when rsvp.status = 'going' then 1 else 0 end)
      - (case when previous = 'going' then 1 else 0 end)
    where a.id = rsvp.activity_id
    returning a.going_count into activity.going_count;
  end if;

  return activity.going_count;
end;
$$;

GRANT EXECUTE ON FUNCTION public.rsvp(uuid, text) TO authenticated;
