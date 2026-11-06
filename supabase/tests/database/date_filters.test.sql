-- Date filters on the feed and search (SRCH-02). Run with `npm run db:test`.
BEGIN;

CREATE EXTENSION IF NOT EXISTS pgtap WITH SCHEMA extensions;

SELECT plan(8);

-- Only this test's activities, until the rollback.
DELETE FROM public.activities;

INSERT INTO auth.users
  (id, email, raw_user_meta_data)
VALUES
  ('c0000000-0000-4000-8000-0000000001d1', 'dee@byui.edu', '{"full_name": "Dee Dates"}');

UPDATE public.profiles
SET
  guidelines_version = 1,
  guidelines_accepted_at = now()
WHERE id = 'c0000000-0000-4000-8000-0000000001d1';

INSERT INTO public.activities
  (organizer_id, category_id, title, starts_at, location_name)
SELECT 'c0000000-0000-4000-8000-0000000001d1', category, title, now() + starts, 'Here'
FROM (
  VALUES
    ('games', 'Last week''s pickleball', INTERVAL '-7 days'),
    ('games', 'Board games soon', INTERVAL '1 hour'),
    ('outdoors', 'Hike tomorrow', INTERVAL '1 day'),
    ('games', 'Pickleball tomorrow', INTERVAL '1 day 1 hour'),
    ('games', 'Pickleball next week', INTERVAL '8 days')
) AS v (category, title, starts);

SET LOCAL ROLE authenticated;

SELECT set_config(
  'request.jwt.claims',
  '{"sub": "c0000000-0000-4000-8000-0000000001d1", "email": "dee@byui.edu"}',
  TRUE
);

-- The feed
SELECT results_eq(
  $$select title from public.get_feed(
    starts_from => now(),
    starts_before => now() + interval '2 days'
  )$$,
  $$values ('Board games soon'), ('Hike tomorrow'), ('Pickleball tomorrow')$$,
  'the feed keeps to the range, soonest first'
);

SELECT results_eq(
  $$select title from public.get_feed(
    category => 'games',
    starts_from => now() + interval '12 hours',
    starts_before => now() + interval '2 days'
  )$$,
  $$values ('Pickleball tomorrow')$$,
  'and combines with a category'
);

SELECT results_eq(
  $$select title from public.get_feed(starts_before => now() + interval '12 hours')$$,
  $$values ('Board games soon')$$,
  'either end can be open'
);

SELECT is_empty(
  $$select from public.get_feed(
    starts_from => now() - interval '8 days',
    starts_before => now() - interval '6 days'
  )$$,
  'and what''s over stays out'
);

-- Search
SELECT results_eq(
  $$select title from public.search_activities(
    'pickleball',
    starts_from => now(),
    starts_before => now() + interval '2 days'
  )$$,
  $$values ('Pickleball tomorrow')$$,
  'search keeps to the range too'
);

SELECT results_eq(
  $$select title from public.search_activities(
    'tomorrow',
    category => 'outdoors',
    starts_from => now(),
    starts_before => now() + interval '2 days'
  )$$,
  $$values ('Hike tomorrow')$$,
  'and with a category'
);

SELECT results_eq(
  $$select title from public.search_activities(
    'pickleball',
    include_past => true,
    starts_from => now() - interval '8 days',
    starts_before => now()
  )$$,
  $$values ('Last week''s pickleball')$$,
  'including a range in the past'
);

SELECT results_eq(
  $$select title from public.search_activities(
    'pickleball',
    starts_from => now() + interval '2 days',
    after_starts_at => now() + interval '1 day',
    after_id => '00000000-0000-4000-8000-000000000000'
  )$$,
  $$values ('Pickleball next week')$$,
  'with a cursor'
);

SELECT *
FROM finish();

ROLLBACK;
