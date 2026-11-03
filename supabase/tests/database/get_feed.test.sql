-- The Home feed (ACT-01). Run with `npm run db:test`.
BEGIN;

CREATE EXTENSION IF NOT EXISTS pgtap WITH SCHEMA extensions;

SELECT plan(8);

-- Only this test's activities, until the rollback.
DELETE FROM public.activities;

-- A member who has accepted the guidelines, and one who hasn't
INSERT INTO auth.users
  (id, email, raw_user_meta_data)
VALUES
  ('c0000000-0000-4000-8000-000000000011', 'fran.feed@byui.edu', '{"full_name": "Fran Feed"}'),
  ('c0000000-0000-4000-8000-000000000012', 'nell.new@byui.edu', '{"full_name": "Nell New"}');

UPDATE public.profiles
SET
  guidelines_version = 1,
  guidelines_accepted_at = now()
WHERE id = 'c0000000-0000-4000-8000-000000000011';

-- Two start at the same time, so their ids decide the order.
INSERT INTO public.activities
  (id, organizer_id, category_id, title, starts_at, location_name, status, cancelled_at, hidden_at)
VALUES
  (
    'e0000000-0000-4000-8000-000000000001',
    'c0000000-0000-4000-8000-000000000011',
    'games',
    'Started 4 hours ago',
    now() - INTERVAL '4 hours',
    'Here',
    'published',
    NULL,
    NULL
  ),
  (
    'e0000000-0000-4000-8000-000000000002',
    'c0000000-0000-4000-8000-000000000011',
    'games',
    'Started 2 hours ago',
    now() - INTERVAL '2 hours',
    'Here',
    'published',
    NULL,
    NULL
  ),
  (
    'e0000000-0000-4000-8000-000000000004',
    'c0000000-0000-4000-8000-000000000011',
    'games',
    'Tomorrow B',
    date_trunc('hour', now()) + INTERVAL '1 day',
    'Here',
    'published',
    NULL,
    NULL
  ),
  (
    'e0000000-0000-4000-8000-000000000003',
    'c0000000-0000-4000-8000-000000000011',
    'games',
    'Tomorrow A',
    date_trunc('hour', now()) + INTERVAL '1 day',
    'Here',
    'published',
    NULL,
    NULL
  ),
  (
    'e0000000-0000-4000-8000-000000000005',
    'c0000000-0000-4000-8000-000000000011',
    'games',
    'Cancelled',
    now() + INTERVAL '2 days',
    'Here',
    'cancelled',
    now(),
    NULL
  ),
  (
    'e0000000-0000-4000-8000-000000000006',
    'c0000000-0000-4000-8000-000000000011',
    'games',
    'Hidden',
    now() + INTERVAL '2 days',
    'Here',
    'published',
    NULL,
    now()
  ),
  (
    'e0000000-0000-4000-8000-000000000007',
    'c0000000-0000-4000-8000-000000000011',
    'games',
    'Next week',
    now() + INTERVAL '7 days',
    'Here',
    'published',
    NULL,
    NULL
  );

SET LOCAL ROLE authenticated;

SELECT set_config(
  'request.jwt.claims',
  '{"sub": "c0000000-0000-4000-8000-000000000011", "email": "fran.feed@byui.edu"}',
  TRUE
);

SELECT results_eq(
  'SELECT title FROM public.get_feed()',
  ARRAY['Started 2 hours ago', 'Tomorrow A', 'Tomorrow B', 'Next week'],
  'the feed starts 3 hours ago, soonest first, without cancelled or hidden activities'
);

SELECT ok(
  EXISTS (
    SELECT
    FROM public.activities
    WHERE title = 'Hidden'
  ),
  'the organizer can read their hidden activity, which the feed still leaves out'
);

SELECT results_eq(
  'SELECT title FROM public.get_feed(page_size => 2)',
  ARRAY['Started 2 hours ago', 'Tomorrow A'],
  'a page holds page_size activities'
);

SELECT results_eq(
  $$SELECT title FROM public.get_feed(
    date_trunc('hour', now()) + interval '1 day',
    'e0000000-0000-4000-8000-000000000003'
  )$$,
  ARRAY['Tomorrow B', 'Next week'],
  'the next page starts after the cursor, even at the same start time'
);

SELECT is_empty(
  $$SELECT title FROM public.get_feed(now() + interval '7 days', 'e0000000-0000-4000-8000-000000000007')$$,
  'the page after the last one is empty'
);

RESET ROLE;

INSERT INTO public.activities
  (organizer_id, category_id, title, starts_at, location_name)
SELECT
  'c0000000-0000-4000-8000-000000000011',
  'games',
  'Game night ' || n,
  now() + n * INTERVAL '1 hour',
  'Here'
FROM generate_series(1, 60) AS n;

SET LOCAL ROLE authenticated;

SELECT extensions.is(
  (
    SELECT count(*)::INTEGER
    FROM public.get_feed(page_size => 100)
  ),
  50,
  'a page holds at most 50 activities'
);

SELECT set_config(
  'request.jwt.claims',
  '{"sub": "c0000000-0000-4000-8000-000000000012", "email": "nell.new@byui.edu"}',
  TRUE
);

SELECT is_empty(
  'SELECT title FROM public.get_feed()',
  'members who have not accepted the guidelines see an empty feed'
);

RESET ROLE;

SELECT ok(
  NOT has_function_privilege('anon', 'public.get_feed(timestamptz, uuid, integer)', 'execute'),
  'signed-out visitors cannot call get_feed'
);

SELECT *
FROM finish();

ROLLBACK;
