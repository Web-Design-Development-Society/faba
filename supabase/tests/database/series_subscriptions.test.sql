-- I'm in for all upcoming (REC-04). Run with `npm run db:test`.
BEGIN;

CREATE EXTENSION IF NOT EXISTS pgtap WITH SCHEMA extensions;

SELECT plan(24);

-- Rae organizes, and Gid, Mel and Sue come along.
INSERT INTO auth.users
  (id, email, raw_user_meta_data)
SELECT
  ('c0000000-0000-4000-8000-00000000049' || n)::uuid,
  name || '@byui.edu',
  jsonb_build_object('full_name', name)
FROM (
  VALUES
    (1, 'rae'),
    (2, 'gid'),
    (3, 'mel'),
    (4, 'sue')
) AS v (n, name);

UPDATE public.profiles
SET
  guidelines_version = 1,
  guidelines_accepted_at = now()
WHERE id::text LIKE 'c0000000-0000-4000-8000-00000000049_';

SET LOCAL ROLE authenticated;

-- Signs in as one of them.
CREATE FUNCTION pg_temp.as_member(n INTEGER)
RETURNS text
LANGUAGE sql
AS $$
  SELECT set_config(
    'request.jwt.claims',
    jsonb_build_object(
      'sub',
      'c0000000-0000-4000-8000-00000000049' || n,
      'email',
      (ARRAY['rae', 'gid', 'mel', 'sue'])[n] || '@byui.edu'
    )::text,
    TRUE
  );
$$;

SELECT pg_temp.as_member(1);

-- Weekly pickleball from tomorrow with 2 spots, the organizer's and one more, an activity on its
-- own, and the series' 8 dates, numbered from the first.
CREATE TABLE pg_temp.posted AS
  SELECT
    public.create_series(
      title => 'Tuesday pickleball',
      category_id => 'sports',
      starts_at => now() + INTERVAL '1 day',
      location_name => 'Hart courts',
      freq => 'weekly',
      capacity => 2
    ) AS id,
    public.create_activity(
      title => 'Sunrise hike',
      category_id => 'outdoors',
      starts_at => now() + INTERVAL '2 days',
      location_name => 'R Mountain trailhead'
    ) AS hike;

CREATE TABLE pg_temp.dates AS
  SELECT row_number() OVER (ORDER BY a.starts_at)::INTEGER AS n, a.id, a.series_id
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

-- The dates of the series, in order, that member `n` is going to. The first 8 are numbered.
CREATE FUNCTION pg_temp.going(n INTEGER)
RETURNS text
LANGUAGE sql
AS $$
  SELECT string_agg(coalesce(x.n::text, 'new'), ' ' ORDER BY a.starts_at)
  FROM public.activities AS a
  JOIN public.rsvps AS r ON r.activity_id = a.id
  LEFT JOIN pg_temp.dates AS x ON x.id = a.id
  WHERE
    a.series_id = (SELECT series_id FROM pg_temp.dates LIMIT 1)
    AND r.user_id = ('c0000000-0000-4000-8000-00000000049' || going.n)::uuid
    AND r.status = 'going';
$$;

SELECT throws_ok(
  $$select public.join_series(pg_temp.d(1))$$,
  '22023',
  'ORGANIZER_GOING',
  'the organizer is going already'
);

-- Mel takes the 3rd date's last spot, and Gid is a maybe for the 2nd.
SELECT pg_temp.as_member(3);

SELECT lives_ok(
  $$select public.rsvp(pg_temp.d(3), 'going')$$,
  'someone takes one date''s last spot'
);

SELECT pg_temp.as_member(2);

SELECT lives_ok(
  $$select public.rsvp(pg_temp.d(2), 'maybe')$$,
  'and someone is a maybe for one date'
);

SELECT throws_ok(
  $$select public.join_series(hike) from pg_temp.posted$$,
  '22023',
  'SERIES_NOT_FOUND',
  'an activity on its own has no series to join'
);

SELECT throws_ok(
  $$select public.join_series('f0000000-0000-4000-8000-000000000499')$$,
  'P0002',
  'ACTIVITY_NOT_FOUND',
  'nor does one that doesn''t exist'
);

SELECT results_eq(
  $$select public.join_series(pg_temp.d(4))$$,
  $$values (7)$$,
  'I''m in for all upcoming, from any date, makes them going to every date with room'
);

SELECT results_eq(
  $$select pg_temp.going(2)$$,
  $$values ('1 2 4 5 6 7 8'::text)$$,
  'the full date is left out, and the maybe is going'
);

SELECT results_eq(
  $$
    select x.n, a.going_count, a.maybe_count
    from public.activities as a
    join pg_temp.dates as x on x.id = a.id
    where x.n in (1, 2, 3)
    order by x.n
  $$,
  $$values (1, 2, 0), (2, 2, 0), (3, 2, 0)$$,
  'each date counts them once'
);

SELECT results_eq(
  $$select public.join_series(pg_temp.d(1))$$,
  $$values (0)$$,
  'joining again adds nothing'
);

SELECT results_eq(
  $$select count(*)::integer from public.series_subscriptions$$,
  $$values (1)$$,
  'they read their subscription'
);

SELECT pg_temp.as_member(4);

SELECT results_eq(
  $$select count(*)::integer from public.series_subscriptions$$,
  $$values (0)$$,
  'and nobody else does'
);

SELECT results_eq(
  $$select public.join_series(pg_temp.d(1))$$,
  $$values (0)$$,
  'someone who joins a series that''s full isn''t going yet'
);

-- Sue joined after Gid.
RESET ROLE;

UPDATE public.series_subscriptions
SET created_at = now() + INTERVAL '1 minute'
WHERE user_id = 'c0000000-0000-4000-8000-000000000494';

SELECT results_eq(
  $$
    select private.generate_occurrences(series_id, now() + interval '14 days')
    from pg_temp.dates
    limit 1
  $$,
  $$values (2)$$,
  'the top-up makes the next dates'
);

SELECT results_eq(
  $$select pg_temp.going(2), pg_temp.going(4)$$,
  $$values ('1 2 4 5 6 7 8 new new'::text, null::text)$$,
  'with whoever joined first going, while there''s room'
);

SELECT results_eq(
  $$
    select distinct a.going_count
    from public.activities as a
    where
      a.series_id = (select series_id from pg_temp.dates limit 1)
      and a.id not in (select id from pg_temp.dates)
  $$,
  $$values (2)$$,
  'and counted'
);

-- Who heard: Gid once, already read (NOTIF-05), and Rae once for Gid and once for Mel (NOTIF-06).
SELECT results_eq(
  $$
    select x.n, n.read_at is not null
    from public.notifications as n
    join pg_temp.dates as x on x.id = n.activity_id
    where n.recipient_id = 'c0000000-0000-4000-8000-000000000492' and n.type = 'rsvp_confirmed'
  $$,
  $$values (1, true)$$,
  'joining confirms once, on the first date, already read'
);

SELECT results_eq(
  $$
    select x.n, (n.payload ->> 'count')::integer
    from public.notifications as n
    join pg_temp.dates as x on x.id = n.activity_id
    where n.recipient_id = 'c0000000-0000-4000-8000-000000000491' and n.type = 'new_attendees'
    order by x.n
  $$,
  $$values (1, 1), (3, 1)$$,
  'and tells the organizer once, on that date'
);

SET LOCAL ROLE authenticated;

SELECT pg_temp.as_member(2);

SELECT results_eq(
  $$select public.leave_series(pg_temp.d(2))$$,
  $$values (9)$$,
  'Leave series takes them out of every upcoming date'
);

SELECT results_eq(
  $$select pg_temp.going(2), (select count(*)::integer from public.series_subscriptions)$$,
  $$values (null::text, 0)$$,
  'and ends their subscription'
);

SELECT results_eq(
  $$
    select distinct a.going_count
    from public.activities as a
    where a.series_id = (select series_id from pg_temp.dates limit 1) and a.id != pg_temp.d(3)
  $$,
  $$values (1)$$,
  'each date has its spot back'
);

SELECT results_eq(
  $$select public.leave_series(pg_temp.d(2))$$,
  $$values (0)$$,
  'leaving again changes nothing'
);

RESET ROLE;

SELECT results_eq(
  $$
    select count(*)::integer
    from public.notifications as n
    where n.recipient_id = 'c0000000-0000-4000-8000-000000000492' and n.type = 'rsvp_confirmed'
  $$,
  $$values (0)$$,
  'and their confirmation goes'
);

SELECT results_eq(
  $$
    select private.generate_occurrences(series_id, now() + interval '21 days')
    from pg_temp.dates
    limit 1
  $$,
  $$values (1)$$,
  'the next top-up'
);

SELECT results_eq(
  $$select pg_temp.going(2), pg_temp.going(4)$$,
  $$values (null::text, 'new'::text)$$,
  'has whoever is still in the series going, and not who left'
);

SELECT *
FROM finish();

ROLLBACK;
