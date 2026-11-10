-- Group activities and who sees them (GRP-03). Design document sections 7.7, 8.3, 9.8 and 10.3,
-- and FR-ACT-11. An organizer of a group can post an activity under it, for everyone (the default)
-- or for the group's members only. RLS on activities decides who sees a group-only one, and RSVPs,
-- updates, tags and details for attendees all read activities through it. rsvp() and
-- announce_activity(), which read activities as their owner, check too.

ALTER TABLE public.activities
ADD COLUMN group_id uuid REFERENCES public.groups (id)
  ON DELETE RESTRICT,
ADD COLUMN visibility text NOT NULL DEFAULT 'members' CHECK (visibility IN ('members', 'group')),
ADD CONSTRAINT activities_group_visibility_check
  CHECK (visibility = 'members' OR group_id IS NOT NULL);

CREATE INDEX activities_group_starts_idx ON public.activities (group_id, starts_at);

-- Members read activities as before (20261105160000_hide_activity.sql), and a
-- group-only one only when they're in the group, or organize it, or moderate.
DROP POLICY "Active members read activities that aren't hidden, and moderators read all" ON public.activities;

CREATE POLICY "Active members read the activities they can see" ON public.activities
FOR SELECT
TO authenticated
USING (
  (SELECT private.is_active_member())
  AND (
    hidden_at IS NULL
    OR organizer_id = (SELECT auth.uid())
    OR (SELECT private.is_moderator()) IS TRUE
  )
  AND (
    visibility = 'members'
    OR organizer_id = (SELECT auth.uid())
    OR (SELECT private.is_moderator()) IS TRUE
    OR private.is_group_member(group_id)
  )
);

-- Saying "I'm in" as before (20261111120000_new_attendees.sql), but not to a group-only activity
-- for someone outside the group.
CREATE OR REPLACE FUNCTION public.rsvp(activity_id uuid, status text, guests INTEGER DEFAULT NULL)
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
  confirmation text := 'rsvp_confirmed:' || rsvp.activity_id;
  -- One batch for each hour, in UTC, such as new_attendees:<id>:2026-11-10T22.
  batch text := 'new_attendees:' || rsvp.activity_id || ':'
    || to_char(date_trunc('hour', now() at time zone 'UTC'), 'YYYY-MM-DD"T"HH24');
  unseen integer;
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

  -- NOTIF-05: going now, and not before, confirms it. Changing only the guests doesn't.
  if rsvp.status = 'going' and previous is distinct from 'going' then
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
  elsif rsvp.status != 'going' and previous = 'going' then
    delete from public.notifications as n
    where n.recipient_id = auth.uid() and n.dedupe_key = confirmation;
  end if;

  return activity.going_count;
end;
$$;

-- Announcing as before (20261111150000_board_activities.sql), but never a group-only activity.
CREATE OR REPLACE FUNCTION public.announce_activity(activity_id uuid)
RETURNS INTEGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
declare
  activity public.activities := private.board_activity(announce_activity.activity_id);
  told integer;
begin
  if not activity.is_board_activity then
    raise exception 'NOT_BOARD_ACTIVITY' using errcode = '22023';
  end if;

  if activity.announced_at is not null then
    raise exception 'ALREADY_ANNOUNCED' using errcode = '22023';
  end if;

  -- A group-only activity is never announced to everyone (GRP-03).
  if activity.status = 'cancelled' or activity.hidden_at is not null or activity.visibility = 'group'
  then
    raise exception 'ANNOUNCE_UNAVAILABLE' using errcode = '22023';
  end if;

  if activity.starts_at <= now() then
    raise exception 'ANNOUNCE_TOO_LATE' using errcode = '22023';
  end if;

  update public.activities as a set announced_at = now() where a.id = activity.id;

  -- One INSERT … SELECT for about 2,600 members.
  told := private.notify(
    array(
      select p.id
      from public.profiles as p
      where p.status = 'active' and p.id != auth.uid()
    ),
    'board_announcement',
    activity.id,
    jsonb_build_object('title', activity.title, 'starts_at', activity.starts_at),
    'board_announcement:' || activity.id
  );

  perform private.audit('announce_activity', 'activity', activity.id, null, jsonb_build_object('told', told));
  return told;
end;
$$;

-- Posting as before (20261111180000_post_again.sql), with a group and who sees it.
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
  text,
  uuid
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
  copied_from_id uuid DEFAULT NULL,
  group_id uuid DEFAULT NULL,
  visibility text DEFAULT 'members'
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

  -- GRP-03: an activity can belong to a group its organizer organizes, which isn't archived or
  -- hidden, and only then be for the group's members.
  if create_activity.visibility is null
    or create_activity.visibility not in ('members', 'group')
    or create_activity.visibility = 'group' and create_activity.group_id is null
  then
    raise exception 'INVALID_VISIBILITY' using errcode = '22023';
  end if;

  if create_activity.group_id is not null and not exists (
    select
    from public.group_members as m
    join public.groups as g on g.id = m.group_id
    where
      m.group_id = create_activity.group_id
      and m.user_id = auth.uid()
      and m.role in ('owner', 'organizer')
      and m.status = 'active'
      and g.archived_at is null
      and g.hidden_at is null
  ) then
    raise exception 'NOT_GROUP_ORGANIZER' using errcode = '42501';
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
    copied_from_id,
    group_id,
    visibility
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
    ),
    create_activity.group_id,
    create_activity.visibility
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
  uuid,
  uuid,
  text
)
TO authenticated;
