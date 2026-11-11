-- Cancelling one date of a series (REC-03). Run with `npm run db:test`.
BEGIN;

CREATE EXTENSION IF NOT EXISTS pgtap WITH SCHEMA extensions;

SELECT plan(11);

-- Rae organizes, and Gid comes along.
INSERT INTO auth.users
  (id, email, raw_user_meta_data)
SELECT
  ('c0000000-0000-4000-8000-00000000048' || n)::uuid,
  name || '@byui.edu',
  jsonb_build_object('full_name', name)
FROM (
  VALUES
    (1, 'rae'),
    (2, 'gid')
) AS v (n, name);

UPDATE public.profiles
SET
  guidelines_version = 1,
  guidelines_accepted_at = now()
WHERE id::text LIKE 'c0000000-0000-4000-8000-00000000048_';

SET LOCAL ROLE authenticated;

SELECT set_config(
  'request.jwt.claims',
  '{"sub": "c0000000-0000-4000-8000-000000000481", "email": "rae@byui.edu"}',
  TRUE
);

-- Weekly pickleball from tomorrow, and its 8 dates, numbered from the first.
CREATE TABLE pg_temp.posted AS
  SELECT public.create_series(
    title => 'Tuesday pickleball',
    category_id => 'sports',
    starts_at => now() + INTERVAL '1 day',
    location_name => 'Hart courts',
    freq => 'weekly'
  ) AS id;

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

-- Gid is going to the 2nd and 3rd dates.
RESET ROLE;

INSERT INTO public.rsvps
  (activity_id, user_id, status)
VALUES
  (pg_temp.d(2), 'c0000000-0000-4000-8000-000000000482', 'going'),
  (pg_temp.d(3), 'c0000000-0000-4000-8000-000000000482', 'going');

CREATE TABLE pg_temp.series_before AS
  SELECT s.*
  FROM public.activity_series AS s
  WHERE s.id = (SELECT series_id FROM pg_temp.dates LIMIT 1);

SET LOCAL ROLE authenticated;

SELECT lives_ok(
  $$select public.cancel_activity(pg_temp.d(2), 'Thanksgiving')$$,
  'the organizer cancels one date'
);

SELECT results_eq(
  $$
    select string_agg(x.n::text, ' ' order by x.n)
    from pg_temp.dates as x
    join public.activities as a on a.id = x.id
    where a.status = 'cancelled'
  $$,
  $$values ('2'::text)$$,
  'only that date is cancelled'
);

SELECT results_eq(
  $$
    select a.cancel_reason, a.series_id is not null, a.series_detached
    from public.activities as a
    where a.id = pg_temp.d(2)
  $$,
  $$values ('Thanksgiving'::text, true, false)$$,
  'with its reason, and it stays in the series'
);

-- A later change to the series reaches the cancelled date, so restoring it finds it up to date.
SELECT results_eq(
  $$
    select public.update_series(
      pg_temp.d(1),
      '{"location_name": "Library courts"}',
      1,
      '{}'
    )
  $$,
  $$values (8)$$,
  'this and future dates still changes it'
);

SELECT lives_ok(
  $$select public.restore_activity(pg_temp.d(2))$$,
  'the organizer restores the date'
);

SELECT results_eq(
  $$select status, location_name from public.activities where id = pg_temp.d(2)$$,
  $$values ('published'::text, 'Library courts'::text)$$,
  'and it''s back on, as the series is now'
);

SELECT lives_ok($$select public.cancel_activity(pg_temp.d(2))$$, 'and cancels it again');

RESET ROLE;

SELECT results_eq(
  $$
    select s.freq, s.start_date, s.until_date, s.generated_through
    from public.activity_series as s
    where s.id = (select series_id from pg_temp.dates limit 1)
  $$,
  $$select b.freq, b.start_date, b.until_date, b.generated_through from pg_temp.series_before as b$$,
  'the series is as it was'
);

SELECT results_eq(
  $$
    select private.generate_occurrences(series_id, now() + interval '14 days')
    from pg_temp.dates
    limit 1
  $$,
  $$values (2)$$,
  'the series continues: the top-up makes the next dates'
);

SELECT results_eq(
  $$
    select count(*)::integer
    from public.activities as a
    join pg_temp.dates as x on x.series_id = a.series_id and x.n = 2
    where (a.starts_at at time zone a.timezone)::date = (x.starts_at at time zone a.timezone)::date
  $$,
  $$values (1)$$,
  'and doesn''t make the cancelled date again'
);

-- Who heard (NOTIF-03): each time the date was cancelled, and not for the change while it was
-- cancelled, which they hear of on the next date they're going to.
SELECT results_eq(
  $$
    select x.n, n.type
    from public.notifications as n
    join pg_temp.dates as x on x.id = n.activity_id
    where
      n.recipient_id = 'c0000000-0000-4000-8000-000000000482'
      and n.type in ('activity_cancelled', 'activity_changed')
    order by x.n, n.type
  $$,
  $$values
    (2, 'activity_cancelled'::text),
    (2, 'activity_cancelled'::text),
    (3, 'activity_changed'::text)$$,
  'someone going hears each time that date is cancelled, and about the change on their next date'
);

SELECT *
FROM finish();

ROLLBACK;
