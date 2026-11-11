-- The waitlist (RSVP-07). Design document sections 7.8, 8.5 and 8.8. A full activity takes Join
-- waitlist in place of I'm in. When a spot opens, because someone leaves, brings fewer guests or
-- the organizer makes room, whoever has waited longest is going, in the same transaction, and gets
-- an unread rsvp_promoted notification. That stops 1 hour before the start, when an open spot goes
-- to whoever says I'm in. A member waiting brings no guests, and reads their place in line. Joining
-- a series (REC-04) waits for its full dates.

ALTER TABLE public.rsvps
DROP CONSTRAINT rsvps_status_check;

ALTER TABLE public.rsvps
ADD CONSTRAINT rsvps_status_check CHECK (status IN ('going', 'maybe', 'not_going', 'waitlisted'));

-- When they joined the waitlist, which is their place in it.
ALTER TABLE public.rsvps
ADD COLUMN waitlisted_at timestamptz;

ALTER TABLE public.rsvps
ADD CONSTRAINT rsvps_waitlisted_at_check
  CHECK ((status = 'waitlisted') = (waitlisted_at IS NOT NULL));

CREATE INDEX rsvps_waitlist_idx ON public.rsvps (activity_id, waitlisted_at)
WHERE status = 'waitlisted';

ALTER TABLE public.notifications
DROP CONSTRAINT notifications_type_check;

ALTER TABLE public.notifications
ADD CONSTRAINT notifications_type_check
  CHECK (
    type IN (
      'activity_changed',
      'activity_cancelled',
      'activity_restored',
      'organizer_update',
      'rsvp_confirmed',
      'new_attendees',
      'reminder',
      'board_announcement',
      'group_join_request',
      'group_update',
      'group_join_approved',
      'group_owner',
      'rsvp_promoted'
    )
  );

-- Saying "I'm in" as before (20261111210000_group_activities.sql), with the waitlist: `waitlisted`
-- joins it when the activity is full, and is going when it isn't.
CREATE OR REPLACE FUNCTION public.rsvp(activity_id uuid, status text, guests INTEGER DEFAULT NULL)
RETURNS INTEGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
declare
  activity public.activities;
  want text := rsvp.status;
  previous text;
  had integer;
  wanted integer;
  confirmation text := 'rsvp_confirmed:' || rsvp.activity_id;
  -- One batch for each hour, in UTC, such as new_attendees:<id>:2026-11-10T22.
  batch text := 'new_attendees:' || rsvp.activity_id || ':'
    || to_char(date_trunc('hour', now() at time zone 'UTC'), 'YYYY-MM-DD"T"HH24');
  unseen integer;
begin
  if not private.is_active_member() then
    raise exception 'NOT_ACTIVE' using errcode = '42501';
  end if;

  if want is null or want not in ('going', 'maybe', 'not_going', 'waitlisted') then
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

  -- Only its organizer can see a hidden activity, and only the group's members can see a group-only
  -- one (GRP-03).
  if activity.hidden_at is not null
    or activity.visibility = 'group' and not private.is_group_member(activity.group_id)
  then
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

  -- Join waitlist (RSVP-07). Someone going stays going, and if a spot opened meanwhile, it's theirs.
  if want = 'waitlisted' then
    if previous = 'going' then
      return activity.going_count;
    end if;

    if activity.capacity is null
      or activity.going_count + activity.guest_total + 1 <= activity.capacity
    then
      want := 'going';
    end if;
  end if;

  wanted := case
    when want != 'going' then 0
    else coalesce(rsvp.guests, case when previous = 'going' then had else 0 end)
  end;

  -- Full, once going and guests reach the capacity. The row is locked above, so two members can't
  -- both take the last spot. Someone going keeps their spot and guests, or brings fewer, even after
  -- the capacity is lowered.
  if want = 'going'
    and (previous is distinct from 'going' or wanted > had)
    and activity.going_count + activity.guest_total
      - (case when previous = 'going' then 1 + had else 0 end)
      + 1 + wanted > activity.capacity
  then
    raise exception 'ACTIVITY_FULL' using errcode = '22023';
  end if;

  -- Joining the waitlist again keeps their place.
  if previous is distinct from want or wanted != had then
    insert into public.rsvps (activity_id, user_id, status, guest_count, waitlisted_at)
    values (
      rsvp.activity_id,
      auth.uid(),
      want,
      wanted,
      case when want = 'waitlisted' then clock_timestamp() end
    )
    on conflict on constraint rsvps_pkey do update
    set
      status = excluded.status,
      guest_count = excluded.guest_count,
      waitlisted_at = excluded.waitlisted_at;

    -- A spot that opens here goes to the waitlist, in promote_waitlist() below.
    update public.activities as a
    set
      going_count = a.going_count
        + (case when want = 'going' then 1 else 0 end)
        - (case when previous = 'going' then 1 else 0 end),
      maybe_count = a.maybe_count
        + (case when want = 'maybe' then 1 else 0 end)
        - (case when previous = 'maybe' then 1 else 0 end),
      guest_total = a.guest_total + wanted - (case when previous = 'going' then had else 0 end)
    where a.id = rsvp.activity_id;
  end if;

  -- NOTIF-05: going now, and not before, confirms it. Changing only the guests doesn't.
  if want = 'going' and previous is distinct from 'going' then
    perform private.notify(
      array[auth.uid()],
      'rsvp_confirmed',
      activity.id,
      jsonb_build_object(
        'title', activity.title,
        'starts_at', activity.starts_at,
        'location_name', activity.location_name
      ),
      confirmation
    );
    -- notify() makes it, or brings it back, unread. This one is read from the start.
    update public.notifications as n
    set read_at = n.created_at
    where n.recipient_id = auth.uid() and n.dedupe_key = confirmation;

    -- NOTIF-06: the organizer gets one notification each hour. It counts who's new since they last read
    -- it, so a read one starts again at 1. The activity is locked above, so two RSVPs can't both
    -- count from the same number.
    select case when n.read_at is null then (n.payload ->> 'count')::integer else 0 end
    into unseen
    from public.notifications as n
    where n.recipient_id = activity.organizer_id and n.dedupe_key = batch;

    perform private.notify(
      array[activity.organizer_id],
      'new_attendees',
      activity.id,
      jsonb_build_object('title', activity.title, 'count', coalesce(unseen, 0) + 1),
      batch
    );
  elsif want != 'going' and previous = 'going' then
    delete from public.notifications as n
    where n.recipient_id = auth.uid() and n.dedupe_key = confirmation;
  end if;

  -- Read again, since the waitlist may have taken the spot.
  return (select a.going_count from public.activities as a where a.id = rsvp.activity_id);
end;
$$;

-- When an activity gets room, whoever has waited longest is going, one at a time while there's
-- room and anyone waiting, until 1 hour before the start. Each gets an unread rsvp_promoted
-- notification, which doesn't name whoever left. It runs in the transaction that made the room,
-- with the activity's row locked, so promotion is atomic and first in, first out.
CREATE FUNCTION private.promote_waitlist()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
declare
  taken INTEGER;
  spots INTEGER;
  next uuid;
begin
  if new.status != 'published'
    or new.hidden_at is not null
    or new.starts_at <= now() + interval '1 hour'
  then
    return null;
  end if;

  loop
    select a.going_count + a.guest_total, a.capacity into taken, spots
    from public.activities as a
    where a.id = new.id;

    exit when taken + 1 > spots;

    select r.user_id into next
    from public.rsvps as r
    join public.profiles as p on p.id = r.user_id
    where r.activity_id = new.id and r.status = 'waitlisted' and p.status = 'active'
    order by r.waitlisted_at, r.user_id
    limit 1;

    exit when not found;

    update public.rsvps as r
    set status = 'going', waitlisted_at = null
    where r.activity_id = new.id and r.user_id = next;

    update public.activities as a
    set going_count = a.going_count + 1
    where a.id = new.id;

    insert into public.notifications (recipient_id, type, activity_id, payload, dedupe_key)
    values (
      next,
      'rsvp_promoted',
      new.id,
      jsonb_build_object(
        'title', new.title,
        'starts_at', new.starts_at,
        'location_name', new.location_name
      ),
      'rsvp_promoted:' || new.id
    )
    on conflict on constraint notifications_recipient_id_dedupe_key_key do update
    set payload = excluded.payload, actor_id = null, created_at = now(), read_at = null;
  end loop;

  return null;
end;
$$;

REVOKE EXECUTE
ON FUNCTION private.promote_waitlist()
FROM PUBLIC, anon, authenticated, service_role;

-- Whatever makes the room: rsvp(), leaving a series, deleting an account, or a new capacity.
CREATE TRIGGER activities_promote_waitlist
AFTER UPDATE OF going_count, guest_total, capacity ON public.activities
FOR EACH ROW
WHEN
  (
    new.capacity IS DISTINCT FROM old.capacity
    OR new.going_count + new.guest_total < old.going_count + old.guest_total
  )
EXECUTE FUNCTION private.promote_waitlist();

-- The signed-in member's place on activity `activity_id`'s waitlist, from 1, or null when they
-- aren't on it. Members can't read who else is waiting.
CREATE FUNCTION public.waitlist_position(activity_id uuid)
RETURNS INTEGER
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = ''
AS $$
  SELECT nullif(count(*), 0)::INTEGER
  FROM public.rsvps AS mine
  JOIN public.rsvps AS r ON r.activity_id = mine.activity_id AND r.status = 'waitlisted'
  JOIN public.profiles AS p ON p.id = r.user_id AND p.status = 'active'
  WHERE
    mine.activity_id = waitlist_position.activity_id
    AND mine.user_id = auth.uid()
    AND mine.status = 'waitlisted'
    AND (r.waitlisted_at, r.user_id) <= (mine.waitlisted_at, mine.user_id);
$$;

REVOKE EXECUTE ON FUNCTION public.waitlist_position(uuid) FROM PUBLIC, anon;

GRANT EXECUTE ON FUNCTION public.waitlist_position(uuid) TO authenticated;

-- Going to a series' date as before (20261112140000_series_subscriptions.sql), and waiting for a
-- full one. Returns whether they're newly going.
CREATE OR REPLACE FUNCTION private.series_rsvp(a public.activities, member uuid)
RETURNS BOOLEAN
LANGUAGE plpgsql
SET search_path = ''
AS $$
declare
  now_at public.activities;
  previous text;
  is_full BOOLEAN;
begin
  -- Locked, so RSVPs to one activity count one at a time, and read again for its counts.
  select * into now_at from public.activities as x where x.id = a.id for update;

  if not found
    or now_at.organizer_id is not distinct from member
    or now_at.status != 'published'
    or now_at.hidden_at is not null
    or coalesce(now_at.ends_at, now_at.starts_at + interval '3 hours') <= now()
    or now_at.visibility = 'group' and not exists (
      select
      from public.group_members as m
      where m.group_id = now_at.group_id and m.user_id = member and m.status = 'active'
    )
    or not exists (
      select from public.profiles as p where p.id = member and p.status = 'active'
    )
  then
    return false;
  end if;

  select r.status into previous
  from public.rsvps as r
  where r.activity_id = now_at.id and r.user_id = member;

  if previous in ('going', 'waitlisted') then
    return false;
  end if;

  is_full := now_at.going_count + now_at.guest_total + 1 > now_at.capacity;

  -- The clock, not the transaction's start, so those added together keep their order.
  insert into public.rsvps (activity_id, user_id, status, guest_count, waitlisted_at)
  values (
    now_at.id,
    member,
    case when is_full then 'waitlisted' else 'going' end,
    0,
    case when is_full then clock_timestamp() end
  )
  on conflict on constraint rsvps_pkey do update
  set
    status = excluded.status,
    guest_count = excluded.guest_count,
    waitlisted_at = excluded.waitlisted_at;

  update public.activities as x
  set
    going_count = x.going_count + (case when is_full then 0 else 1 end),
    maybe_count = x.maybe_count - (case when previous = 'maybe' then 1 else 0 end)
  where x.id = now_at.id;

  return is_full is not true;
end;
$$;

-- Leaving a series as before, and its dates' waitlists.
CREATE OR REPLACE FUNCTION public.leave_series(activity_id uuid)
RETURNS INTEGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
declare
  series uuid;
  o record;
  made INTEGER := 0;
begin
  if not private.is_active_member() then
    raise exception 'NOT_ACTIVE' using errcode = '42501';
  end if;

  select a.series_id into series
  from public.activities as a
  where a.id = leave_series.activity_id;

  if series is null then
    raise exception 'SERIES_NOT_FOUND' using errcode = '22023';
  end if;

  delete from public.series_subscriptions as s
  where s.series_id = series and s.user_id = auth.uid();

  -- Each date locked, so RSVPs to it count one at a time.
  for o in
    select a.id
    from public.activities as a
    where
      a.series_id = series
      and a.starts_at > now()
      and a.organizer_id is distinct from auth.uid()
    order by a.starts_at
    for update
  loop
    with left_date as (
      delete from public.rsvps as r
      where
        r.activity_id = o.id
        and r.user_id = auth.uid()
        and r.status in ('going', 'waitlisted')
      returning r.status, r.guest_count
    )
    update public.activities as a
    set
      going_count = a.going_count - (case when l.status = 'going' then 1 else 0 end),
      guest_total = a.guest_total - l.guest_count
    from left_date as l
    where a.id = o.id;

    continue when not found;

    delete from public.notifications as n
    where n.recipient_id = auth.uid() and n.dedupe_key = 'rsvp_confirmed:' || o.id;

    made := made + 1;
  end loop;

  return made;
end;
$$;
