-- Recurring activities (REC-01). Design document sections 7.7, 9.12 and 10.3, and journey J9. An
-- organizer posts a series once: weekly, every 2 weeks, or monthly on the same date or the same
-- weekday (such as the 2nd Tuesday), ending on a date up to 12 months after the first or rolling
-- on. Each date is an ordinary activity, with the series' details, the organizer going, its tags
-- and its details for attendees. Dates are made 8 weeks ahead, when the series is posted and then
-- every day by pg_cron, so a rolling series always has its next 8 weeks on Discover. Dates are
-- worked out on the series' calendar, in its time zone, so 7:00 PM stays 7:00 PM when the clocks
-- change.

CREATE TABLE public.activity_series (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  -- The series stays, and stops making dates, when its organizer deletes their account.
  organizer_id uuid REFERENCES public.profiles (id)
    ON DELETE SET NULL,
  group_id uuid REFERENCES public.groups (id)
    ON DELETE RESTRICT,
  visibility text NOT NULL DEFAULT 'members' CHECK (visibility IN ('members', 'group')),
  -- What each date is made from, with the activities table's limits.
  category_id text NOT NULL REFERENCES public.categories (id),
  title text NOT NULL CHECK (char_length(title) BETWEEN 3 AND 80),
  description text CHECK (char_length(description) <= 2000),
  location_name text NOT NULL CHECK (char_length(location_name) BETWEEN 1 AND 120),
  cost_note text CHECK (char_length(cost_note) <= 60),
  capacity INTEGER CHECK (capacity BETWEEN 1 AND 500),
  guests_allowed BOOLEAN NOT NULL DEFAULT FALSE,
  max_guests_per_rsvp INTEGER NOT NULL DEFAULT 5 CHECK (max_guests_per_rsvp BETWEEN 1 AND 5),
  tag_ids text[] NOT NULL DEFAULT '{}' CHECK (cardinality(tag_ids) <= 3),
  -- When it repeats: on the first date's weekday every week or 2 weeks, or every month on its
  -- date or on its weekday (the 2nd Tuesday, say, and a 5th one means the last).
  freq text NOT NULL CHECK (freq IN ('weekly', 'biweekly', 'monthly_date', 'monthly_nth')),
  start_date date NOT NULL,
  start_time TIME NOT NULL,
  -- How long each date lasts, or null without an end time.
  duration INTERVAL CHECK (duration > INTERVAL '0'),
  timezone text NOT NULL DEFAULT 'America/Denver',
  -- The last date it can fall on, or null to roll on.
  until_date date CHECK (
    until_date >= start_date
    AND until_date <= start_date + INTERVAL '12 months'
  ),
  -- Dates through this one have been made. The daily top-up moves it forward.
  generated_through date NOT NULL,
  idempotency_key uuid,
  created_at timestamptz NOT NULL DEFAULT now(),
  CONSTRAINT activity_series_group_visibility_check
    CHECK (visibility = 'members' OR group_id IS NOT NULL)
);

CREATE UNIQUE INDEX activity_series_idempotency_idx
ON public.activity_series (organizer_id, idempotency_key);

CREATE INDEX activity_series_organizer_created_idx
ON public.activity_series (organizer_id, created_at);

CREATE INDEX activity_series_generated_through_idx ON public.activity_series (generated_through);

CREATE INDEX activity_series_group_idx ON public.activity_series (group_id);

-- The series' details for attendees (ACT-09), such as a gate code, which each date gets. They live
-- in the private schema, which the Data API never exposes, so members who read the series can't
-- read them.
CREATE TABLE private.series_private_details (
  series_id uuid PRIMARY KEY REFERENCES public.activity_series (id)
    ON DELETE CASCADE,
  details text NOT NULL CHECK (char_length(details) BETWEEN 1 AND 500)
);

REVOKE ALL ON private.series_private_details FROM PUBLIC, anon, authenticated, service_role;

ALTER TABLE private.series_private_details ENABLE ROW LEVEL SECURITY;

ALTER TABLE public.activity_series ENABLE ROW LEVEL SECURITY;

-- Members read a series as they read its activities (20261111210000_group_activities.sql), so a
-- card can say Weekly. It's changed only through functions.
CREATE POLICY "Active members read the series they can see" ON public.activity_series
FOR SELECT
TO authenticated
USING (
  (SELECT private.is_active_member())
  AND (
    visibility = 'members'
    OR organizer_id = (SELECT auth.uid())
    OR (SELECT private.is_moderator()) IS TRUE
    OR private.is_group_member(group_id)
  )
);

-- Each date knows its series. Deleting a series, which nothing does yet, leaves its dates as
-- ordinary activities.
ALTER TABLE public.activities
ADD COLUMN series_id uuid REFERENCES public.activity_series (id)
  ON DELETE SET NULL;

CREATE INDEX activities_series_starts_idx ON public.activities (series_id, starts_at);

-- The `n`th `weekday` (0 is Sunday) of the month that `month`, its first day, starts, and the last
-- one when `n` is 5.
CREATE FUNCTION private.nth_weekday(month date, weekday INTEGER, n INTEGER)
RETURNS date
LANGUAGE sql
IMMUTABLE
SET search_path = ''
AS $$
  SELECT CASE
    WHEN n >= 5 THEN last_day - ((EXTRACT(DOW FROM last_day)::INTEGER - weekday + 7) % 7)
    ELSE first + (n - 1) * 7
  END
  FROM (
    SELECT
      month + ((weekday - EXTRACT(DOW FROM month)::INTEGER + 7) % 7) AS first,
      (month + INTERVAL '1 month - 1 day')::date AS last_day
  ) AS days;
$$;

REVOKE EXECUTE
ON FUNCTION private.nth_weekday(date, INTEGER, INTEGER)
FROM PUBLIC, anon, authenticated, service_role;

-- Every date series `s` falls on, from its first through `through` and its last date. A month
-- without the date, such as a 31st, is skipped.
CREATE FUNCTION private.series_dates(s public.activity_series, through date)
RETURNS SETOF date
LANGUAGE sql
STABLE
SET search_path = ''
AS $$
  WITH
    months AS (
      SELECT m::date AS month
      FROM generate_series(
        date_trunc('month', s.start_date)::TIMESTAMP,
        through::TIMESTAMP,
        INTERVAL '1 month'
      ) AS g (m)
    ),
    dates AS (
      SELECT d::date AS d
      FROM generate_series(s.start_date::TIMESTAMP, through::TIMESTAMP, INTERVAL '7 days') AS g (d)
      WHERE s.freq = 'weekly'
      UNION ALL
      SELECT d::date
      FROM generate_series(s.start_date::TIMESTAMP, through::TIMESTAMP, INTERVAL '14 days') AS g (d)
      WHERE s.freq = 'biweekly'
      UNION ALL
      SELECT month + (EXTRACT(DAY FROM s.start_date)::INTEGER - 1)
      FROM months
      WHERE
        s.freq = 'monthly_date'
        AND EXTRACT(DAY FROM s.start_date) <= EXTRACT(DAY FROM month + INTERVAL '1 month - 1 day')
      UNION ALL
      SELECT private.nth_weekday(
        month,
        EXTRACT(DOW FROM s.start_date)::INTEGER,
        (EXTRACT(DAY FROM s.start_date)::INTEGER - 1) / 7 + 1
      )
      FROM months
      WHERE s.freq = 'monthly_nth'
    )
  SELECT d
  FROM dates
  WHERE d >= s.start_date AND d <= through AND (s.until_date IS NULL OR d <= s.until_date)
  ORDER BY d;
$$;

REVOKE EXECUTE
ON FUNCTION private.series_dates(public.activity_series, date)
FROM PUBLIC, anon, authenticated, service_role;

-- Makes series `series_id`'s dates through 8 weeks from `as_of`, on its calendar, and its last
-- date, skipping the ones it has. Each is an activity with the series' details, its organizer
-- going, its tags and its details for attendees. A date that has started by `as_of` is left out.
-- Returns how many it made.
CREATE FUNCTION private.generate_occurrences(series_id uuid, as_of timestamptz DEFAULT now())
RETURNS INTEGER
LANGUAGE plpgsql
SET search_path = ''
AS $$
declare
  s public.activity_series;
  through date;
  details text;
  d date;
  starts timestamptz;
  new_id uuid;
  made integer := 0;
begin
  select * into s
  from public.activity_series as x
  where x.id = generate_occurrences.series_id
  for update;

  if not found then
    return 0;
  end if;

  through := least((as_of at time zone s.timezone)::date + 56, s.until_date);

  if through <= s.generated_through then
    return 0;
  end if;

  select p.details into details
  from private.series_private_details as p
  where p.series_id = s.id;

  for d in
    select x.d from private.series_dates(s, through) as x (d) where x.d > s.generated_through
  loop
    -- The wall clock on that date, in the series' time zone, whatever the offset is then.
    starts := (d + s.start_time) at time zone s.timezone;

    continue when starts <= as_of;

    insert into public.activities (
      organizer_id,
      category_id,
      title,
      description,
      starts_at,
      ends_at,
      timezone,
      location_name,
      cost_note,
      going_count,
      capacity,
      guests_allowed,
      max_guests_per_rsvp,
      group_id,
      visibility,
      series_id
    )
    values (
      s.organizer_id,
      s.category_id,
      s.title,
      s.description,
      starts,
      starts + s.duration,
      s.timezone,
      s.location_name,
      s.cost_note,
      1,
      s.capacity,
      s.guests_allowed,
      s.max_guests_per_rsvp,
      s.group_id,
      s.visibility,
      s.id
    )
    returning id into new_id;

    insert into public.rsvps (activity_id, user_id, status)
    values (new_id, s.organizer_id, 'going');

    insert into public.activity_tags (activity_id, tag_id)
    select new_id, t.id
    from unnest(s.tag_ids) as t (id);

    perform private.set_private_details(new_id, details);

    made := made + 1;
  end loop;

  update public.activity_series as x
  set generated_through = through
  where x.id = s.id;

  return made;
end;
$$;

REVOKE EXECUTE
ON FUNCTION private.generate_occurrences(uuid, timestamptz)
FROM PUBLIC, anon, authenticated, service_role;

-- Tops up every series that has dates to make: its organizer is active, its group isn't archived
-- or hidden, and it hasn't reached its last date. Returns how many dates it made.
CREATE FUNCTION private.top_up_series(as_of timestamptz DEFAULT now())
RETURNS INTEGER
LANGUAGE plpgsql
SET search_path = ''
AS $$
declare
  series_id uuid;
  made integer := 0;
begin
  for series_id in
    select s.id
    from public.activity_series as s
    join public.profiles as p on p.id = s.organizer_id and p.status = 'active'
    left join public.groups as g on g.id = s.group_id
    where
      s.generated_through < least((as_of at time zone s.timezone)::date + 56, s.until_date)
      and (s.group_id is null or g.archived_at is null and g.hidden_at is null)
    order by s.created_at
  loop
    made := made + private.generate_occurrences(series_id, as_of);
  end loop;
  return made;
end;
$$;

REVOKE EXECUTE
ON FUNCTION private.top_up_series(timestamptz)
FROM PUBLIC, anon, authenticated, service_role;

-- Every day at 9:00 UTC, which is 2:00 or 3:00 AM in Rexburg.
SELECT cron.schedule('top-up-series', '0 9 * * *', 'select private.top_up_series()');

-- The checks a new activity passes, shared by create_activity() and create_series(): its category
-- is offered, its group is one the member organizes (GRP-03), it starts in the future and in the
-- next 12 months, it ends after it starts, and its spots and guests are within limits.
CREATE FUNCTION private.check_new_activity(
  category_id text,
  group_id uuid,
  visibility text,
  starts_at timestamptz,
  ends_at timestamptz,
  capacity INTEGER,
  max_guests_per_rsvp INTEGER
)
RETURNS void
LANGUAGE plpgsql
SET search_path = ''
AS $$
begin
  if not exists (
    select from public.categories as c
    where c.id = check_new_activity.category_id and c.is_active
  ) then
    raise exception 'INVALID_CATEGORY' using errcode = '22023';
  end if;

  if check_new_activity.visibility is null
    or check_new_activity.visibility not in ('members', 'group')
    or check_new_activity.visibility = 'group' and check_new_activity.group_id is null
  then
    raise exception 'INVALID_VISIBILITY' using errcode = '22023';
  end if;

  if check_new_activity.group_id is not null and not exists (
    select
    from public.group_members as m
    join public.groups as g on g.id = m.group_id
    where
      m.group_id = check_new_activity.group_id
      and m.user_id = auth.uid()
      and m.role in ('owner', 'organizer')
      and m.status = 'active'
      and g.archived_at is null
      and g.hidden_at is null
  ) then
    raise exception 'NOT_GROUP_ORGANIZER' using errcode = '42501';
  end if;

  if check_new_activity.starts_at <= now() then
    raise exception 'START_IN_PAST' using errcode = '22023';
  end if;

  if check_new_activity.starts_at > now() + interval '12 months' then
    raise exception 'START_TOO_FAR' using errcode = '22023';
  end if;

  if check_new_activity.ends_at <= check_new_activity.starts_at then
    raise exception 'END_BEFORE_START' using errcode = '22023';
  end if;

  if check_new_activity.capacity not between 1 and 500 then
    raise exception 'INVALID_CAPACITY' using errcode = '22023';
  end if;

  if check_new_activity.max_guests_per_rsvp not between 1 and 5 then
    raise exception 'INVALID_GUESTS' using errcode = '22023';
  end if;
end;
$$;

REVOKE EXECUTE
ON FUNCTION private.check_new_activity(text, uuid, text, timestamptz, timestamptz, INTEGER, INTEGER)
FROM PUBLIC, anon, authenticated, service_role;

-- At most 10 posts in 24 hours (FR-ACT-5), where a series is one post however many dates it makes.
CREATE FUNCTION private.check_post_quota()
RETURNS void
LANGUAGE plpgsql
SET search_path = ''
AS $$
begin
  if (
    select count(*)
    from public.activities as a
    where
      a.organizer_id = auth.uid()
      and a.created_at > now() - interval '24 hours'
      and a.series_id is null
  ) + (
    select count(*)
    from public.activity_series as s
    where s.organizer_id = auth.uid() and s.created_at > now() - interval '24 hours'
  ) >= 10 then
    raise exception 'QUOTA_EXCEEDED' using errcode = 'P0001';
  end if;
end;
$$;

REVOKE EXECUTE
ON FUNCTION private.check_post_quota()
FROM PUBLIC, anon, authenticated, service_role;

-- Posting as before (20261111210000_group_activities.sql), with the checks shared, and a series'
-- dates left out of the daily limit.
CREATE OR REPLACE FUNCTION public.create_activity(
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

  perform private.check_new_activity(
    create_activity.category_id,
    create_activity.group_id,
    create_activity.visibility,
    create_activity.starts_at,
    create_activity.ends_at,
    create_activity.capacity,
    create_activity.max_guests_per_rsvp
  );
  perform private.check_post_quota();

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

-- Posts a series: an activity that repeats as `freq` says, from `starts_at` through `until_date`
-- or rolling on, with `tag_ids` on every date. Its first 8 weeks of dates are made at once.
-- Returns the first date's activity, so posting lands on it as it does for one activity.
CREATE FUNCTION public.create_series(
  title text,
  category_id text,
  starts_at timestamptz,
  location_name text,
  freq text,
  description text DEFAULT NULL,
  ends_at timestamptz DEFAULT NULL,
  cost_note text DEFAULT NULL,
  idempotency_key uuid DEFAULT NULL,
  capacity INTEGER DEFAULT NULL,
  guests_allowed BOOLEAN DEFAULT FALSE,
  max_guests_per_rsvp INTEGER DEFAULT 5,
  private_details text DEFAULT NULL,
  group_id uuid DEFAULT NULL,
  visibility text DEFAULT 'members',
  until_date date DEFAULT NULL,
  tag_ids text[] DEFAULT NULL
)
RETURNS uuid
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
declare
  tz text := 'America/Denver';
  first_date date := (create_series.starts_at at time zone tz)::date;
  details text := nullif(btrim(create_series.private_details, E' \t\r\n'), '');
  wanted text[] := array(select distinct unnest(coalesce(create_series.tag_ids, '{}')));
  new_series uuid;
begin
  if not private.is_active_member() then
    raise exception 'NOT_ACTIVE' using errcode = '42501';
  end if;

  -- The same lock as create_activity(), since they share the daily limit.
  perform pg_advisory_xact_lock(hashtextextended('create_activity ' || auth.uid(), 0));

  if create_series.idempotency_key is not null then
    select s.id into new_series
    from public.activity_series as s
    where s.organizer_id = auth.uid() and s.idempotency_key = create_series.idempotency_key;

    if found then
      return (
        select a.id
        from public.activities as a
        where a.series_id = new_series
        order by a.starts_at
        limit 1
      );
    end if;
  end if;

  perform private.check_new_activity(
    create_series.category_id,
    create_series.group_id,
    create_series.visibility,
    create_series.starts_at,
    create_series.ends_at,
    create_series.capacity,
    create_series.max_guests_per_rsvp
  );
  perform private.check_post_quota();

  if create_series.freq is null
    or create_series.freq not in ('weekly', 'biweekly', 'monthly_date', 'monthly_nth')
  then
    raise exception 'INVALID_REPEATS' using errcode = '22023';
  end if;

  if create_series.until_date < first_date then
    raise exception 'UNTIL_BEFORE_START' using errcode = '22023';
  end if;

  if create_series.until_date > first_date + interval '12 months' then
    raise exception 'SERIES_TOO_LONG' using errcode = '22023';
  end if;

  if cardinality(wanted) > 3 then
    raise exception 'TOO_MANY_TAGS' using errcode = '22023';
  end if;

  if exists (
    select from unnest(wanted) as w (id)
    where not exists (select from public.tags as g where g.id = w.id and g.is_active)
  ) then
    raise exception 'INVALID_TAG' using errcode = '22023';
  end if;

  if char_length(details) > 500 then
    raise exception 'INVALID_PRIVATE_DETAILS' using errcode = '22023';
  end if;

  insert into public.activity_series (
    organizer_id,
    group_id,
    visibility,
    category_id,
    title,
    description,
    location_name,
    cost_note,
    capacity,
    guests_allowed,
    max_guests_per_rsvp,
    tag_ids,
    freq,
    start_date,
    start_time,
    duration,
    timezone,
    until_date,
    generated_through,
    idempotency_key
  )
  values (
    auth.uid(),
    create_series.group_id,
    create_series.visibility,
    create_series.category_id,
    trim(create_series.title),
    nullif(trim(create_series.description), ''),
    trim(create_series.location_name),
    nullif(trim(create_series.cost_note), ''),
    create_series.capacity,
    coalesce(create_series.guests_allowed, false),
    coalesce(create_series.max_guests_per_rsvp, 5),
    wanted,
    create_series.freq,
    first_date,
    (create_series.starts_at at time zone tz)::time,
    create_series.ends_at - create_series.starts_at,
    tz,
    create_series.until_date,
    first_date - 1,
    create_series.idempotency_key
  )
  returning id into new_series;

  if details is not null then
    insert into private.series_private_details (series_id, details)
    values (new_series, details);
  end if;

  perform private.generate_occurrences(new_series);

  return (
    select a.id
    from public.activities as a
    where a.series_id = new_series
    order by a.starts_at
    limit 1
  );
end;
$$;

GRANT EXECUTE
ON FUNCTION public.create_series(
  text,
  text,
  timestamptz,
  text,
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
  text,
  date,
  text[]
)
TO authenticated;
