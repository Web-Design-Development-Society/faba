-- Board analytics (ANLY-01). Run with `npm run db:test`.
BEGIN;

CREATE EXTENSION IF NOT EXISTS pgtap WITH SCHEMA extensions;

SELECT plan(4);

-- A day with a few members doesn't store anything below 10: small groups are never kept.
SELECT cmp_ok(
  private.compute_daily_metrics(DATE '2026-11-10'),
  '>=',
  0,
  'the day''s metrics compute'
);

SELECT results_eq(
  $$select count(*) from public.daily_metrics where value < 10$$,
  $$values (0::bigint)$$,
  'no stored group is smaller than 10'
);

-- Ten sign-ups on one day are stored as a new-members count.
INSERT INTO auth.users (id, email, raw_user_meta_data)
SELECT
  ('c0000000-0000-4000-8000-0000000019' || lpad(n::text, 2, '0'))::uuid,
  'member' || n || '@byui.edu',
  '{"full_name": "Metric Member"}'
FROM generate_series(1, 10) AS n;

UPDATE public.profiles
SET created_at = '2026-11-09 15:00:00+00'::timestamptz
WHERE id::text LIKE 'c0000000-0000-4000-8000-0000000019%';

SELECT private.compute_daily_metrics(DATE '2026-11-09');

SELECT results_eq(
  $$select value from public.daily_metrics where day = date '2026-11-09' and metric = 'new_members'$$,
  $$values (10)$$,
  'ten new members on a day are stored'
);

SET LOCAL ROLE authenticated;

SELECT results_eq(
  $$select count(*) from public.daily_metrics$$,
  $$values (0::bigint)$$,
  'a member who isn''t a moderator reads no metrics'
);

ROLLBACK;
