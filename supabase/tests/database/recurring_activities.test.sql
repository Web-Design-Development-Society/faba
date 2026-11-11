-- Recurring activities (REC-01). Run with `npm run db:test`.
BEGIN;

CREATE EXTENSION IF NOT EXISTS pgtap WITH SCHEMA extensions;

SELECT plan(36);

-- Rae organizes, Gid is in her group Runners, and Out isn't.
INSERT INTO auth.users
  (id, email, raw_user_meta_data)
SELECT
  ('c0000000-0000-4000-8000-00000000046' || n)::uuid,
  name || '@byui.edu',
  jsonb_build_object('full_name', name)
FROM (
  VALUES
    (1, 'rae'),
    (2, 'gid'),
    (3, 'out')
) AS v (n, name);

UPDATE public.profiles
SET
  guidelines_version = 1,
  guidelines_accepted_at = now()
WHERE id::text LIKE 'c0000000-0000-4000-8000-00000000046_';

INSERT INTO public.groups
  (id, slug, name, category_id, owner_id)
VALUES
  (
    'b0000000-0000-4000-8000-000000000461',
    'runners-461',
    'Runners',
    'outdoors',
    'c0000000-0000-4000-8000-000000000461'
  );

INSERT INTO public.group_members
  (group_id, user_id, role)
VALUES
  ('b0000000-0000-4000-8000-000000000461', 'c0000000-0000-4000-8000-000000000461', 'owner'),
  ('b0000000-0000-4000-8000-000000000461', 'c0000000-0000-4000-8000-000000000462', 'member');

-- Every date a pattern falls on, from its first date through `through` and its last date.
CREATE FUNCTION pg_temp.dates(
  freq text,
  start_date date,
  through date,
  until_date date DEFAULT NULL
)
RETURNS text
LANGUAGE sql
AS $$
  SELECT string_agg(d::text, ' ' ORDER BY d)
  FROM
    jsonb_populate_record(
      NULL::public.activity_series,
      jsonb_build_object('freq', freq, 'start_date', start_date, 'until_date', until_date)
    ) AS s,
    private.series_dates(s, through) AS d;
$$;

SELECT results_eq(
  $$select pg_temp.dates('weekly', '2027-03-07', '2027-03-28')$$,
  $$values ('2027-03-07 2027-03-14 2027-03-21 2027-03-28'::text)$$,
  'weekly falls on the same weekday'
);

SELECT results_eq(
  $$select pg_temp.dates('biweekly', '2027-03-07', '2027-05-30', '2027-04-10')$$,
  $$values ('2027-03-07 2027-03-21 2027-04-04'::text)$$,
  'every 2 weeks stops at the last date'
);

SELECT results_eq(
  $$select pg_temp.dates('monthly_date', '2027-01-31', '2027-06-30')$$,
  $$values ('2027-01-31 2027-03-31 2027-05-31'::text)$$,
  'monthly on the same date skips a month without it'
);

SELECT results_eq(
  $$select pg_temp.dates('monthly_nth', '2027-01-12', '2027-04-30')$$,
  $$values ('2027-01-12 2027-02-09 2027-03-09 2027-04-13'::text)$$,
  'monthly on the 2nd Tuesday'
);

SELECT results_eq(
  $$select pg_temp.dates('monthly_nth', '2027-01-29', '2027-04-30')$$,
  $$values ('2027-01-29 2027-02-26 2027-03-26 2027-04-30'::text)$$,
  'and a 5th Friday is the last one each month'
);

-- Sunday pickleball at 7 PM through the spring clock change, and game night through the fall one,
-- both posted a while ago, so they don't count toward today's limit.
INSERT INTO public.activity_series
  (
    id,
    organizer_id,
    category_id,
    title,
    location_name,
    tag_ids,
    freq,
    start_date,
    start_time,
    duration,
    until_date,
    generated_through,
    created_at
  )
VALUES
  (
    'e0000000-0000-4000-8000-000000000461',
    'c0000000-0000-4000-8000-000000000461',
    'sports',
    'Sunday pickleball',
    'Hart courts',
    '{free}',
    'weekly',
    '2027-03-07',
    '19:00',
    '90 minutes',
    NULL,
    '2027-03-06',
    now() - INTERVAL '2 days'
  ),
  (
    'e0000000-0000-4000-8000-000000000462',
    'c0000000-0000-4000-8000-000000000461',
    'games',
    'Fall game night',
    'Library',
    '{}',
    'weekly',
    '2027-10-31',
    '19:00',
    NULL,
    '2027-11-07',
    '2027-10-30',
    now() - INTERVAL '2 days'
  );

INSERT INTO private.series_private_details
  (series_id, details)
VALUES
  ('e0000000-0000-4000-8000-000000000461', 'Court 3');

SELECT results_eq(
  $$select private.generate_occurrences('e0000000-0000-4000-8000-000000000461', '2027-03-01 12:00-07')$$,
  $$values (8)$$,
  'posting makes the dates in the next 8 weeks'
);

SELECT results_eq(
  $$
    select min(starts_at), max(starts_at), bool_and((starts_at at time zone timezone)::time = '19:00')
    from public.activities
    where series_id = 'e0000000-0000-4000-8000-000000000461'
  $$,
  $$values ('2027-03-07 19:00-07'::timestamptz, '2027-04-25 19:00-06'::timestamptz, true)$$,
  'the first is at 7 PM before the clocks spring forward, the last at 7 PM after, and every one at 7 PM'
);

SELECT results_eq(
  $$
    select ends_at - starts_at, going_count, has_private_details, category_id, title, location_name
    from public.activities
    where series_id = 'e0000000-0000-4000-8000-000000000461'
    order by starts_at
    limit 1
  $$,
  $$values ('90 minutes'::interval, 1, true, 'sports'::text, 'Sunday pickleball'::text, 'Hart courts'::text)$$,
  'each lasts as long and has the series'' details'
);

SELECT results_eq(
  $$
    select count(*)::integer
    from public.rsvps as r
    join public.activities as a on a.id = r.activity_id
    where
      a.series_id = 'e0000000-0000-4000-8000-000000000461'
      and r.user_id = 'c0000000-0000-4000-8000-000000000461'
      and r.status = 'going'
  $$,
  $$values (8)$$,
  'the organizer is going to each'
);

SELECT results_eq(
  $$
    select count(*)::integer
    from public.activity_tags as t
    join public.activities as a on a.id = t.activity_id
    where a.series_id = 'e0000000-0000-4000-8000-000000000461' and t.tag_id = 'free'
  $$,
  $$values (8)$$,
  'with its tags'
);

SELECT results_eq(
  $$
    select count(*)::integer
    from public.activity_private_details as d
    join public.activities as a on a.id = d.activity_id
    where a.series_id = 'e0000000-0000-4000-8000-000000000461' and d.details = 'Court 3'
  $$,
  $$values (8)$$,
  'and its details for attendees'
);

SELECT results_eq(
  $$select generated_through from public.activity_series where id = 'e0000000-0000-4000-8000-000000000461'$$,
  $$values ('2027-04-26'::date)$$,
  'the series knows how far it''s got'
);

SELECT results_eq(
  $$select private.generate_occurrences('e0000000-0000-4000-8000-000000000461', '2027-03-01 12:00-07')$$,
  $$values (0)$$,
  'and makes no more the same day'
);

SELECT results_eq(
  $$select private.top_up_series('2027-03-09 02:00-07')$$,
  $$values (1)$$,
  'the daily top-up adds the next date'
);

SELECT results_eq(
  $$select private.generate_occurrences('e0000000-0000-4000-8000-000000000462', '2027-10-25 12:00-06')$$,
  $$values (2)$$,
  'a series with a last date stops there'
);

SELECT results_eq(
  $$
    select starts_at, ends_at
    from public.activities
    where series_id = 'e0000000-0000-4000-8000-000000000462'
    order by starts_at
  $$,
  $$values
    ('2027-10-31 19:00-06'::timestamptz, null::timestamptz),
    ('2027-11-07 19:00-07'::timestamptz, null::timestamptz)$$,
  'the clocks fall back, 7 PM stays 7 PM, and no end time means none'
);

UPDATE public.profiles
SET status = 'suspended'
WHERE id = 'c0000000-0000-4000-8000-000000000461';

SELECT results_eq(
  $$select private.top_up_series('2027-03-16 02:00-06')$$,
  $$values (0)$$,
  'not while its organizer is suspended'
);

UPDATE public.profiles
SET status = 'active'
WHERE id = 'c0000000-0000-4000-8000-000000000461';

SELECT results_eq(
  $$select private.top_up_series('2027-03-16 02:00-06')$$,
  $$values (1)$$,
  'and again once they''re back'
);

UPDATE public.activity_series
SET group_id = 'b0000000-0000-4000-8000-000000000461'
WHERE id = 'e0000000-0000-4000-8000-000000000461';

UPDATE public.groups
SET archived_at = now()
WHERE id = 'b0000000-0000-4000-8000-000000000461';

SELECT results_eq(
  $$select private.top_up_series('2027-03-23 02:00-06')$$,
  $$values (0)$$,
  'nor while its group is archived'
);

UPDATE public.groups
SET archived_at = NULL
WHERE id = 'b0000000-0000-4000-8000-000000000461';

SET LOCAL ROLE authenticated;

SELECT set_config(
  'request.jwt.claims',
  '{"sub": "c0000000-0000-4000-8000-000000000461", "email": "rae@byui.edu"}',
  TRUE
);

-- Posts Tuesday pickleball, tomorrow at this time, for Runners, with any arguments changed.
CREATE FUNCTION pg_temp.post(
  freq text DEFAULT 'weekly',
  until_date date DEFAULT NULL,
  tag_ids text[] DEFAULT '{free}',
  idempotency_key uuid DEFAULT NULL,
  visibility text DEFAULT 'group',
  group_id uuid DEFAULT 'b0000000-0000-4000-8000-000000000461'
)
RETURNS uuid
LANGUAGE sql
AS $$
  SELECT public.create_series(
    title => '  Tuesday pickleball ',
    category_id => 'sports',
    starts_at => now() + INTERVAL '1 day',
    location_name => 'Hart courts',
    freq => post.freq,
    ends_at => now() + INTERVAL '1 day 2 hours',
    idempotency_key => post.idempotency_key,
    private_details => ' Court 3 ',
    group_id => post.group_id,
    visibility => post.visibility,
    until_date => post.until_date,
    tag_ids => post.tag_ids
  );
$$;

CREATE TABLE pg_temp.posted AS
  SELECT pg_temp.post(idempotency_key => 'd0000000-0000-4000-8000-000000000461') AS id;

SELECT results_eq(
  $$select id from pg_temp.posted$$,
  $$
    select a.id
    from public.activities as a
    join public.activity_series as s on s.id = a.series_id
    where s.idempotency_key = 'd0000000-0000-4000-8000-000000000461'
    order by a.starts_at
    limit 1
  $$,
  'an organizer posts a weekly series and lands on its first date'
);

SELECT results_eq(
  $$
    select title, location_name, freq, visibility, tag_ids, duration, until_date, start_date
    from public.activity_series
    where idempotency_key = 'd0000000-0000-4000-8000-000000000461'
  $$,
  $$
    values (
      'Tuesday pickleball'::text,
      'Hart courts'::text,
      'weekly'::text,
      'group'::text,
      '{free}'::text[],
      '2 hours'::interval,
      null::date,
      ((now() + interval '1 day') at time zone 'America/Denver')::date
    )
  $$,
  'it keeps the trimmed details, how it repeats, and its first date in Rexburg'
);

SELECT results_eq(
  $$
    select
      count(*)::integer,
      min(a.starts_at),
      bool_and(a.visibility = 'group' and a.group_id = 'b0000000-0000-4000-8000-000000000461'),
      bool_and(a.has_private_details)
    from public.activities as a
    join public.activity_series as s on s.id = a.series_id
    where s.idempotency_key = 'd0000000-0000-4000-8000-000000000461'
  $$,
  $$values (8, now() + interval '1 day', true, true)$$,
  '8 dates, the first at the time posted, all for the group with details for attendees'
);

SELECT results_eq(
  $$select pg_temp.post(idempotency_key => 'd0000000-0000-4000-8000-000000000461')$$,
  $$select id from pg_temp.posted$$,
  'posting again with the same key finds the first date'
);

SELECT results_eq(
  $$
    select count(*)::integer
    from public.activity_series
    where organizer_id = 'c0000000-0000-4000-8000-000000000461' and idempotency_key is not null
  $$,
  $$values (1)$$,
  'and makes no second series'
);

SELECT throws_ok(
  $$select pg_temp.post(freq => 'daily')$$,
  '22023',
  'INVALID_REPEATS',
  'it repeats weekly, every 2 weeks or monthly'
);

SELECT throws_ok(
  $$select pg_temp.post(until_date => (now() at time zone 'America/Denver')::date)$$,
  '22023',
  'UNTIL_BEFORE_START',
  'the last date comes on or after the first'
);

SELECT throws_ok(
  $$select pg_temp.post(until_date => ((now() + interval '13 months') at time zone 'America/Denver')::date)$$,
  '22023',
  'SERIES_TOO_LONG',
  'and within 12 months of it'
);

SELECT throws_ok(
  $$select pg_temp.post(tag_ids => '{a,b,c,d}')$$,
  '22023',
  'TOO_MANY_TAGS',
  'up to 3 tags'
);

SELECT throws_ok(
  $$select pg_temp.post(tag_ids => '{no-such-tag}')$$,
  '22023',
  'INVALID_TAG',
  'which are offered'
);

SELECT throws_ok(
  $$select pg_temp.post(group_id => null)$$,
  '22023',
  'INVALID_VISIBILITY',
  'and the checks a single activity passes'
);

SELECT lives_ok(
  $$
    select public.create_activity(
      'Game night ' || g,
      'games',
      now() + interval '2 days',
      'Library',
      idempotency_key => gen_random_uuid()
    )
    from generate_series(1, 9) as g
  $$,
  'the series counts as one post, so 9 more fit in the day'
);

SELECT throws_ok(
  $$select public.create_activity('Game night', 'games', now() + interval '2 days', 'Library')$$,
  'P0001',
  'QUOTA_EXCEEDED',
  'and an 11th post is one too many'
);

SELECT set_config(
  'request.jwt.claims',
  '{"sub": "c0000000-0000-4000-8000-000000000462", "email": "gid@byui.edu"}',
  TRUE
);

SELECT results_eq(
  $$select freq from public.activity_series where idempotency_key = 'd0000000-0000-4000-8000-000000000461'$$,
  $$values ('weekly'::text)$$,
  'a group member reads the group''s series'
);

SELECT set_config(
  'request.jwt.claims',
  '{"sub": "c0000000-0000-4000-8000-000000000463", "email": "out@byui.edu"}',
  TRUE
);

SELECT is_empty(
  $$select from public.activity_series where idempotency_key = 'd0000000-0000-4000-8000-000000000461'$$,
  'but someone outside the group can''t'
);

SELECT results_eq(
  $$select title from public.activity_series where id = 'e0000000-0000-4000-8000-000000000461'$$,
  $$values ('Sunday pickleball'::text)$$,
  'and reads one for everyone'
);

SELECT throws_ok(
  $$select from private.series_private_details$$,
  '42501',
  NULL,
  'nobody reads a series'' details for attendees through the API'
);

SELECT *
FROM finish();

ROLLBACK;
