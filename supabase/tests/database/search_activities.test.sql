-- Searching activities by keyword (SRCH-01). Run with `npm run db:test`.
BEGIN;

CREATE EXTENSION IF NOT EXISTS pgtap WITH SCHEMA extensions;

SELECT plan(15);

-- Hana Host and Ben organize, and Ivan left BYU-Idaho. The seed has activities too, so each test
-- looks only at these.
INSERT INTO auth.users
  (id, email, raw_user_meta_data)
SELECT
  ('c0000000-0000-4000-8000-0000000001c' || n)::uuid,
  email,
  jsonb_build_object('full_name', name)
FROM (
  VALUES
    (1, 'hana@byui.edu', 'Hana Host'),
    (2, 'ben@byui.edu', 'Ben Boardgamer'),
    (3, 'ivan@byui.edu', 'Ivan Ineligible')
) AS v (n, email, name);

UPDATE public.profiles
SET
  guidelines_version = 1,
  guidelines_accepted_at = now(),
  status = CASE id
    WHEN 'c0000000-0000-4000-8000-0000000001c3' THEN 'ineligible'
    ELSE 'active'
  END
WHERE id::text LIKE 'c0000000-0000-4000-8000-0000000001c_';

INSERT INTO public.activities
  (
    id,
    organizer_id,
    category_id,
    title,
    description,
    starts_at,
    location_name,
    status,
    cancelled_at,
    hidden_at
  )
SELECT
  ('f0000000-0000-4000-8000-0000000001c' || n)::uuid,
  ('c0000000-0000-4000-8000-0000000001c' || organizer)::uuid,
  'games',
  title,
  description,
  now() + starts,
  place,
  status,
  CASE
    WHEN status = 'cancelled' THEN now()
  END,
  hidden
FROM (
  VALUES
    (
      1,
      1,
      'Lunch pickleball',
      'Bring a paddle.',
      INTERVAL '1 day',
      'Hart courts',
      'published',
      NULL::timestamptz
    ),
    (
      2,
      2,
      'Board games',
      'Pickleball after, if it''s warm.',
      INTERVAL '2 days',
      'Library',
      'published',
      NULL
    ),
    (3, 1, 'Sunrise hike', NULL, INTERVAL '3 days', 'R Mountain', 'published', NULL),
    (4, 1, 'Pickleball league night', NULL, INTERVAL '-2 days', 'Hart courts', 'published', NULL),
    (5, 1, 'Pickleball, called off', NULL, INTERVAL '1 day', 'Hart courts', 'cancelled', NULL),
    (6, 1, 'Pickleball for sale', NULL, INTERVAL '1 day', 'Hart courts', 'published', now()),
    (7, 3, 'Swim', NULL, INTERVAL '1 day', 'Pool', 'published', NULL)
) AS v (n, organizer, title, description, starts, place, status, hidden);

SET LOCAL ROLE authenticated;

SELECT set_config(
  'request.jwt.claims',
  '{"sub": "c0000000-0000-4000-8000-0000000001c2", "email": "ben@byui.edu"}',
  TRUE
);

-- Matching
SELECT results_eq(
  $$select title from public.search_activities('pickle')
  where id::text like 'f0000000-0000-4000-8000-0000000001c_'$$,
  $$values ('Lunch pickleball'), ('Board games')$$,
  'the last word matches as a prefix, in the title or the description, soonest first'
);

SELECT results_eq(
  $$select title from public.search_activities('Hiking')
  where id::text like 'f0000000-0000-4000-8000-0000000001c_'$$,
  $$values ('Sunrise hike')$$,
  'words match in any form, whatever the case'
);

SELECT results_eq(
  $$select title from public.search_activities('hart')
  where id::text like 'f0000000-0000-4000-8000-0000000001c_'$$,
  $$values ('Lunch pickleball')$$,
  'the place matches'
);

SELECT results_eq(
  $$select title from public.search_activities('hana host')
  where id::text like 'f0000000-0000-4000-8000-0000000001c_'$$,
  $$values ('Lunch pickleball'), ('Sunrise hike')$$,
  'and the organizer''s name'
);

SELECT results_eq(
  $$select title from public.search_activities('hana pickle')
  where id::text like 'f0000000-0000-4000-8000-0000000001c_'$$,
  $$values ('Lunch pickleball')$$,
  'or both together'
);

SELECT is_empty(
  $$select from public.search_activities('ivan')
  where id::text like 'f0000000-0000-4000-8000-0000000001c_'$$,
  'but not the name of an organizer members can''t read'
);

SELECT is_empty(
  $$select from public.search_activities('pickleball mountain')
  where id::text like 'f0000000-0000-4000-8000-0000000001c_'$$,
  'every word must match'
);

SELECT is_empty(
  $$select from public.search_activities(' (!) ')
  where id::text like 'f0000000-0000-4000-8000-0000000001c_'$$,
  'punctuation alone matches nothing'
);

SELECT is_empty(
  $$select from public.search_activities('the')
  where id::text like 'f0000000-0000-4000-8000-0000000001c_'$$,
  'nor does a common word alone'
);

-- Past activities and pages
SELECT results_eq(
  $$select title from public.search_activities('pickleball', include_past => true)
  where id::text like 'f0000000-0000-4000-8000-0000000001c_'$$,
  $$values ('Board games'), ('Lunch pickleball'), ('Pickleball league night')$$,
  'with past ones, newest first, but never cancelled or hidden ones'
);

SELECT results_eq(
  $$select title from public.search_activities(
    'pickleball',
    after_starts_at => (select starts_at from public.activities where title = 'Lunch pickleball'),
    after_id => 'f0000000-0000-4000-8000-0000000001c1',
    page_size => 1
  )
  where id::text like 'f0000000-0000-4000-8000-0000000001c_'$$,
  $$values ('Board games')$$,
  'the next page starts after the cursor'
);

SELECT results_eq(
  $$select title from public.search_activities(
    'pickleball',
    include_past => true,
    after_starts_at => (select starts_at from public.activities where title = 'Lunch pickleball'),
    after_id => 'f0000000-0000-4000-8000-0000000001c1'
  )
  where id::text like 'f0000000-0000-4000-8000-0000000001c_'$$,
  $$values ('Pickleball league night')$$,
  'including past ones'
);

RESET ROLE;

UPDATE public.activities
SET title = 'Sunrise trail run'
WHERE id = 'f0000000-0000-4000-8000-0000000001c3';

SET LOCAL ROLE authenticated;

SELECT results_eq(
  $$select title from public.search_activities('running')
  where id::text like 'f0000000-0000-4000-8000-0000000001c_'$$,
  $$values ('Sunrise trail run')$$,
  'an edited title matches at once'
);

SELECT set_config('request.jwt.claims', '', TRUE);

SELECT is_empty(
  $$select from public.search_activities('pickleball')
  where id::text like 'f0000000-0000-4000-8000-0000000001c_'$$,
  'without an active member, nothing matches'
);

RESET ROLE;

SELECT function_privs_are(
  'public',
  'search_activities',
  ARRAY[
    'text',
    'boolean',
    'timestamp with time zone',
    'uuid',
    'integer',
    'timestamp with time zone',
    'timestamp with time zone',
    'text'
  ],
  'anon',
  ARRAY[]::text[],
  'visitors can''t search'
);

SELECT *
FROM finish();

ROLLBACK;
