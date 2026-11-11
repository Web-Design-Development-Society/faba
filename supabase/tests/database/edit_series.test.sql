-- Editing one date or the series (REC-02). Run with `npm run db:test`.
BEGIN;

CREATE EXTENSION IF NOT EXISTS pgtap WITH SCHEMA extensions;

SELECT plan(30);

-- Rae organizes, and Gid and Mel come along.
INSERT INTO auth.users
  (id, email, raw_user_meta_data)
SELECT
  ('c0000000-0000-4000-8000-00000000047' || n)::uuid,
  name || '@byui.edu',
  jsonb_build_object('full_name', name)
FROM (
  VALUES
    (1, 'rae'),
    (2, 'gid'),
    (3, 'mel')
) AS v (n, name);

UPDATE public.profiles
SET
  guidelines_version = 1,
  guidelines_accepted_at = now()
WHERE id::text LIKE 'c0000000-0000-4000-8000-00000000047_';

SET LOCAL ROLE authenticated;

SELECT set_config(
  'request.jwt.claims',
  '{"sub": "c0000000-0000-4000-8000-000000000471", "email": "rae@byui.edu"}',
  TRUE
);

-- Tuesday pickleball, from tomorrow at this time for 2 hours, with a tag and a court.
CREATE FUNCTION pg_temp.post(freq text DEFAULT 'weekly')
RETURNS uuid
LANGUAGE sql
AS $$
  SELECT public.create_series(
    title => 'Tuesday pickleball',
    category_id => 'sports',
    starts_at => now() + INTERVAL '1 day',
    location_name => 'Hart courts',
    freq => post.freq,
    ends_at => now() + INTERVAL '1 day 2 hours',
    private_details => 'Court 3',
    tag_ids => '{free}'
  );
$$;

-- The weekly series' 8 dates, numbered from the first, as they were posted.
CREATE TABLE pg_temp.posted AS
  SELECT pg_temp.post() AS id;

CREATE TABLE pg_temp.dates AS
  SELECT row_number() OVER (ORDER BY a.starts_at)::INTEGER AS n, a.id, a.starts_at, a.series_id
  FROM public.activities AS a
  WHERE
    a.series_id = (
      SELECT first.series_id
      FROM public.activities AS first
      JOIN pg_temp.posted AS p ON p.id = first.id
    );

CREATE FUNCTION pg_temp.d(n INTEGER)
RETURNS uuid
LANGUAGE sql
AS $$
  SELECT id FROM pg_temp.dates AS x WHERE x.n = d.n;
$$;

CREATE FUNCTION pg_temp.version(n INTEGER)
RETURNS INTEGER
LANGUAGE sql
AS $$
  SELECT version FROM public.activities WHERE id = pg_temp.d(n);
$$;

SELECT results_eq(
  $$select count(*)::integer from pg_temp.dates$$,
  $$values (8)$$,
  'the series has 8 dates'
);

-- Gid is going to the 2nd, 3rd and 4th dates, and Mel is a maybe for the 4th.
RESET ROLE;

INSERT INTO public.rsvps
  (activity_id, user_id, status)
VALUES
  (pg_temp.d(2), 'c0000000-0000-4000-8000-000000000472', 'going'),
  (pg_temp.d(3), 'c0000000-0000-4000-8000-000000000472', 'going'),
  (pg_temp.d(4), 'c0000000-0000-4000-8000-000000000472', 'going'),
  (pg_temp.d(4), 'c0000000-0000-4000-8000-000000000473', 'maybe');

SET LOCAL ROLE authenticated;

-- Just this date.
SELECT lives_ok(
  $$select public.update_activity(pg_temp.d(3), '{"location_name": "Library"}', 1)$$,
  'the organizer changes one date'
);

SELECT results_eq(
  $$select series_detached, series_id is not null from public.activities where id = pg_temp.d(3)$$,
  $$values (true, true)$$,
  'which detaches it, and it stays in the series'
);

SELECT lives_ok(
  $$select public.update_activity(pg_temp.d(2), '{"location_name": "Hart courts"}', 1)$$,
  'a save that changes nothing'
);

SELECT results_eq(
  $$select series_detached from public.activities where id = pg_temp.d(2)$$,
  $$values (false)$$,
  'leaves a date following the series'
);

SELECT lives_ok(
  $$select public.set_activity_tags(pg_temp.d(5), '{}')$$,
  'the organizer changes one date''s tags'
);

SELECT results_eq(
  $$select series_detached from public.activities where id = pg_temp.d(5)$$,
  $$values (true)$$,
  'which detaches it too'
);

-- This and future dates.
SELECT throws_ok(
  $$select public.update_series(pg_temp.d(2), '{"title": "Thursday pickleball"}', 1, '{free}')$$,
  '40001',
  'STALE_EDIT',
  'a save from an older page fails'
);

SELECT throws_ok(
  $$select public.update_series(pg_temp.d(3), '{"title": "Thursday pickleball"}', pg_temp.version(3), '{free}')$$,
  '22023',
  'NOT_IN_SERIES',
  'a detached date can''t change the series'
);

SELECT throws_ok(
  $$select public.update_series(pg_temp.d(2), '{"series_detached": true}', pg_temp.version(2), '{free}')$$,
  '22023',
  'INVALID_FIELD',
  'only the form''s fields can change'
);

SELECT throws_ok(
  $$select public.update_series(pg_temp.d(2), '{}', pg_temp.version(2), '{free,nope}')$$,
  '22023',
  'INVALID_TAG',
  'its tags are ones on offer'
);

SELECT set_config(
  'request.jwt.claims',
  '{"sub": "c0000000-0000-4000-8000-000000000472", "email": "gid@byui.edu"}',
  TRUE
);

SELECT throws_ok(
  $$select public.update_series(pg_temp.d(2), '{"title": "Gid''s pickleball"}', 2, '{}')$$,
  '42501',
  'NOT_ORGANIZER',
  'only the organizer can'
);

SELECT set_config(
  'request.jwt.claims',
  '{"sub": "c0000000-0000-4000-8000-000000000471", "email": "rae@byui.edu"}',
  TRUE
);

-- From the 2nd date on: 2 days and 30 minutes later, for 1 hour, with a new title and no tags.
SELECT results_eq(
  $$
    select public.update_series(
      pg_temp.d(2),
      jsonb_build_object(
        'title', ' Thursday pickleball ',
        'starts_at', starts_at + interval '2 days 30 minutes',
        'ends_at', starts_at + interval '2 days 90 minutes',
        'capacity', 12
      ),
      pg_temp.version(2),
      '{}'
    )
    from pg_temp.dates
    where n = 2
  $$,
  $$values (5)$$,
  'this and future dates changes every later date that isn''t detached'
);

SELECT results_eq(
  $$
    select string_agg(x.n::text, ' ' order by x.n)
    from pg_temp.dates as x
    join public.activities as a on a.id = x.id
    where a.title = 'Thursday pickleball' and a.capacity = 12
  $$,
  $$values ('2 4 6 7 8'::text)$$,
  'the earlier date and the detached ones keep theirs'
);

SELECT results_eq(
  $$
    select
      count(distinct (a.starts_at at time zone a.timezone)::time)::integer,
      count(distinct extract(dow from a.starts_at at time zone a.timezone))::integer,
      bool_and(a.ends_at - a.starts_at = interval '1 hour'),
      bool_and(a.time_or_place_changed_at is not null)
    from pg_temp.dates as x
    join public.activities as a on a.id = x.id
    where x.n in (2, 4, 6, 7, 8)
  $$,
  $$values (1, 1, true, true)$$,
  'they share the new time, weekday and length'
);

SELECT results_eq(
  $$
    select
      (later.starts_at at time zone later.timezone)::date
        - (first.starts_at at time zone first.timezone)::date
    from public.activities as first, public.activities as later
    where first.id = pg_temp.d(2) and later.id = pg_temp.d(4)
  $$,
  $$values (14)$$,
  'and stay as many days apart'
);

SELECT results_eq(
  $$
    select a.starts_at = x.starts_at, a.location_name
    from pg_temp.dates as x
    join public.activities as a on a.id = x.id
    where x.n = 3
  $$,
  $$values (true, 'Library'::text)$$,
  'the detached date stays where it was'
);

SELECT results_eq(
  $$
    select count(*)::integer
    from public.activity_tags as t
    join pg_temp.dates as x on x.id = t.activity_id
    where x.n in (2, 4, 6, 7, 8)
  $$,
  $$values (0)$$,
  'the changed dates have the new tags'
);

SELECT results_eq(
  $$
    select r.status
    from public.rsvps as r
    where r.activity_id = pg_temp.d(4)
    order by r.status
  $$,
  $$values ('going'::text), ('going'::text), ('maybe'::text)$$,
  'everyone going or maybe stays so'
);

SELECT results_eq(
  $$
    select public.update_series(
      pg_temp.d(2),
      '{"private_details": " Court 5 "}',
      pg_temp.version(2),
      '{}'
    )
  $$,
  $$values (5)$$,
  'the series'' details for attendees change'
);

-- An activity on its own, and a monthly series.
CREATE TABLE pg_temp.others AS
  SELECT
    public.create_activity(
      title => 'Sunrise hike',
      category_id => 'outdoors',
      starts_at => now() + INTERVAL '2 days',
      location_name => 'R Mountain trailhead'
    ) AS hike,
    pg_temp.post('monthly_date') AS monthly;

SELECT throws_ok(
  $$select public.update_series(hike, '{"title": "Sunset hike"}', 1, '{}') from pg_temp.others$$,
  '22023',
  'NOT_IN_SERIES',
  'an activity on its own has no series to change'
);

SELECT throws_ok(
  $$
    select public.update_series(
      monthly,
      jsonb_build_object('starts_at', now() + interval '2 days', 'ends_at', null),
      1,
      '{free}'
    )
    from pg_temp.others
  $$,
  '22023',
  'MONTHLY_DATE_FIXED',
  'a monthly series stays on its day'
);

SELECT results_eq(
  $$
    select public.update_series(
      monthly,
      -- A minute later on the same day, so the series keeps its day even just before midnight.
      jsonb_build_object(
        'starts_at', (SELECT a.starts_at FROM public.activities AS a WHERE a.id = monthly) + interval '1 minute',
        'ends_at', (SELECT a.ends_at FROM public.activities AS a WHERE a.id = monthly) + interval '1 minute'
      ),
      1,
      '{free}'
    ) >= 1
    from pg_temp.others
  $$,
  $$values (true)$$,
  'but its time can change'
);

RESET ROLE;

SELECT results_eq(
  $$
    select
      s.title,
      s.capacity,
      s.tag_ids,
      s.duration,
      s.until_date,
      s.start_date - (select (x.starts_at at time zone s.timezone)::date from pg_temp.dates as x where x.n = 1),
      s.generated_through >= (
        select max((a.starts_at at time zone s.timezone)::date)
        from public.activities as a
        where a.series_id = s.id and not a.series_detached
      )
    from public.activity_series as s
    where s.id = (select series_id from pg_temp.dates limit 1)
  $$,
  $$values ('Thursday pickleball'::text, 12, '{}'::text[], '1 hour'::interval, null::date, 2, true)$$,
  'the series has the changes, still rolls on, and moved with its dates'
);

SELECT results_eq(
  $$
    select p.details
    from private.series_private_details as p
    where p.series_id = (select series_id from pg_temp.dates limit 1)
  $$,
  $$values ('Court 5'::text)$$,
  'and the new details for attendees'
);

SELECT results_eq(
  $$
    select string_agg(x.n::text, ' ' order by x.n)
    from pg_temp.dates as x
    join public.activity_private_details as d on d.activity_id = x.id
    where d.details = 'Court 5'
  $$,
  $$values ('2 4 6 7 8'::text)$$,
  'as do its dates'
);

-- The dates made later follow the series.
SELECT results_eq(
  $$
    select private.generate_occurrences(series_id, now() + interval '14 days') > 0
    from pg_temp.dates
    limit 1
  $$,
  $$values (true)$$,
  'the top-up makes more dates'
);

SELECT results_eq(
  $$
    select
      bool_and(a.title = 'Thursday pickleball'),
      bool_and(
        (a.starts_at at time zone a.timezone)::time
          = (first.starts_at at time zone first.timezone)::time
      ),
      bool_and(
        extract(dow from a.starts_at at time zone a.timezone)
          = extract(dow from first.starts_at at time zone first.timezone)
      )
    from public.activities as a, public.activities as first
    where
      first.id = pg_temp.d(2)
      and a.series_id = first.series_id
      and a.id not in (select id from pg_temp.dates)
  $$,
  $$values (true, true, true)$$,
  'with the new title, at the new time, on the new weekday'
);

-- Who heard (NOTIF-02).
SELECT results_eq(
  $$
    select x.n, n.payload ? 'series', n.payload ? 'details_changed'
    from public.notifications as n
    join pg_temp.dates as x on x.id = n.activity_id
    where
      n.recipient_id = 'c0000000-0000-4000-8000-000000000472'
      and n.type = 'activity_changed'
    order by x.n
  $$,
  $$values (2, true, true), (3, false, false)$$,
  'someone going hears once about the series, on their first changed date, and about the one date'
);

SELECT results_eq(
  $$
    select x.n, n.payload -> 'before' ->> 'location_name', n.payload ->> 'title'
    from public.notifications as n
    join pg_temp.dates as x on x.id = n.activity_id
    where
      n.recipient_id = 'c0000000-0000-4000-8000-000000000473'
      and n.type = 'activity_changed'
  $$,
  $$values (4, 'Hart courts'::text, 'Thursday pickleball'::text)$$,
  'and a maybe hears on theirs'
);

SELECT *
FROM finish();

ROLLBACK;
