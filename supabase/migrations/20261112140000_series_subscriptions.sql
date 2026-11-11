-- I'm in for all upcoming (REC-04). Design document sections 8.5 and 9.12, and journey J9. A member
-- joins a series once: they're going to every upcoming date they can go to, and to each date the
-- series makes later, until they leave it. Leave series takes them out of its upcoming dates.
-- Capacity is each date's own, so a full date is left out. The waitlist (RSVP-07) will take those.

CREATE TABLE public.series_subscriptions (
  series_id uuid NOT NULL REFERENCES public.activity_series (id)
    ON DELETE CASCADE,
  user_id uuid NOT NULL REFERENCES public.profiles (id)
    ON DELETE CASCADE,
  created_at timestamptz NOT NULL DEFAULT now(),
  PRIMARY KEY (series_id, user_id)
);

CREATE INDEX series_subscriptions_user_idx ON public.series_subscriptions (user_id);

ALTER TABLE public.series_subscriptions ENABLE ROW LEVEL SECURITY;

-- A member reads their own. They're changed only through functions.
CREATE POLICY "Members read their own series subscriptions" ON public.series_subscriptions
FOR SELECT
TO authenticated
USING (user_id = (SELECT auth.uid()));

-- Makes `member` going to activity `a` for its series, with rsvp()'s rules, and keeps its counts.
-- It leaves out a date that's cancelled, hidden, over or full, one for a group they aren't in, and
-- their own. It makes no notifications. Returns whether they're newly going.
CREATE FUNCTION private.series_rsvp(a public.activities, member uuid)
RETURNS BOOLEAN
LANGUAGE plpgsql
SET search_path = ''
AS $$
declare
  now_at public.activities;
  previous text;
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

  if previous = 'going' or now_at.going_count + now_at.guest_total + 1 > now_at.capacity then
    return false;
  end if;

  insert into public.rsvps (activity_id, user_id, status, guest_count)
  values (now_at.id, member, 'going', 0)
  on conflict on constraint rsvps_pkey do update
  set status = excluded.status, guest_count = excluded.guest_count;

  update public.activities as x
  set
    going_count = x.going_count + 1,
    maybe_count = x.maybe_count - (case when previous = 'maybe' then 1 else 0 end)
  where x.id = now_at.id;

  return true;
end;
$$;

REVOKE EXECUTE
ON FUNCTION private.series_rsvp(public.activities, uuid)
FROM PUBLIC, anon, authenticated, service_role;

-- Joins the series that activity `activity_id` is a date in: the member is going to each of its
-- upcoming dates that has room, whatever they'd answered, and to the dates it makes later. Joining
-- again adds the dates they've since left. The member gets one confirmation, already read
-- (NOTIF-05), and the organizer one line in this hour's new attendees (NOTIF-06), both on the first
-- date joined. Returns how many dates they're newly going to.
CREATE FUNCTION public.join_series(activity_id uuid)
RETURNS INTEGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
declare
  activity public.activities;
  o public.activities;
  first public.activities;
  batch text;
  unseen INTEGER;
  made INTEGER := 0;
begin
  if not private.is_active_member() then
    raise exception 'NOT_ACTIVE' using errcode = '42501';
  end if;

  select * into activity from public.activities as a where a.id = join_series.activity_id;

  -- Only its organizer can see a hidden activity, and only the group's members can see a group-only
  -- one (GRP-03), as rsvp() says.
  if not found
    or activity.hidden_at is not null
    or activity.visibility = 'group' and not private.is_group_member(activity.group_id)
  then
    raise exception 'ACTIVITY_NOT_FOUND' using errcode = 'P0002';
  end if;

  if activity.series_id is null then
    raise exception 'SERIES_NOT_FOUND' using errcode = '22023';
  end if;

  -- The organizer went when they posted it, and stays going (RSVP-02).
  if activity.organizer_id = auth.uid() then
    raise exception 'ORGANIZER_GOING' using errcode = '22023';
  end if;

  insert into public.series_subscriptions (series_id, user_id)
  values (activity.series_id, auth.uid())
  on conflict do nothing;

  for o in
    select a.*
    from public.activities as a
    where a.series_id = activity.series_id and a.starts_at > now()
    order by a.starts_at
  loop
    if private.series_rsvp(o, auth.uid()) then
      made := made + 1;
      if first.id is null then
        first := o;
      end if;
    end if;
  end loop;

  if first.id is not null then
    perform private.notify(
      array[auth.uid()],
      'rsvp_confirmed',
      first.id,
      jsonb_build_object(
        'title', first.title,
        'starts_at', first.starts_at,
        'location_name', first.location_name
      ),
      'rsvp_confirmed:' || first.id
    );

    update public.notifications as n
    set read_at = n.created_at
    where n.recipient_id = auth.uid() and n.dedupe_key = 'rsvp_confirmed:' || first.id;

    -- One batch for each hour, in UTC, as rsvp() counts them.
    batch := 'new_attendees:' || first.id || ':'
      || to_char(date_trunc('hour', now() at time zone 'UTC'), 'YYYY-MM-DD"T"HH24');

    select case when n.read_at is null then (n.payload ->> 'count')::integer else 0 end
    into unseen
    from public.notifications as n
    where n.recipient_id = first.organizer_id and n.dedupe_key = batch;

    perform private.notify(
      array[first.organizer_id],
      'new_attendees',
      first.id,
      jsonb_build_object('title', first.title, 'count', coalesce(unseen, 0) + 1),
      batch
    );
  end if;

  return made;
end;
$$;

GRANT EXECUTE ON FUNCTION public.join_series(uuid) TO authenticated;

-- Leaves the series that activity `activity_id` is a date in: the member isn't going to its
-- upcoming dates any more, guests and all, and its later dates don't add them. Dates that have
-- started stay as they were. Returns how many dates they left.
CREATE FUNCTION public.leave_series(activity_id uuid)
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
      where r.activity_id = o.id and r.user_id = auth.uid() and r.status = 'going'
      returning r.guest_count
    )
    update public.activities as a
    set going_count = a.going_count - 1, guest_total = a.guest_total - l.guest_count
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

GRANT EXECUTE ON FUNCTION public.leave_series(uuid) TO authenticated;

-- A date the series makes later has everyone who joined it going, first come first, while it has
-- room.
CREATE FUNCTION private.add_series_subscribers()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
declare
  member uuid;
begin
  for member in
    select s.user_id
    from public.series_subscriptions as s
    where s.series_id = new.series_id
    order by s.created_at
  loop
    perform private.series_rsvp(new, member);
  end loop;
  return null;
end;
$$;

REVOKE EXECUTE
ON FUNCTION private.add_series_subscribers()
FROM PUBLIC, anon, authenticated, service_role;

CREATE TRIGGER activities_add_series_subscribers
AFTER INSERT ON public.activities
FOR EACH ROW
WHEN (new.series_id IS NOT NULL)
EXECUTE FUNCTION private.add_series_subscribers();
