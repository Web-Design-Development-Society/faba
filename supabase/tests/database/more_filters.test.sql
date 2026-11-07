-- More filters on the feed and search (SRCH-03). Run with `npm run db:test`.
BEGIN;

CREATE EXTENSION IF NOT EXISTS pgtap WITH SCHEMA extensions;

SELECT plan(8);

-- Only this test's activities, until the rollback.
DELETE FROM public.activities;

INSERT INTO auth.users
  (id, email, raw_user_meta_data)
VALUES
  ('c0000000-0000-4000-8000-000000000211', 'mo@byui.edu', '{"full_name": "Mo Filters"}');

UPDATE public.profiles
SET
  guidelines_version = 1,
  guidelines_accepted_at = now()
WHERE id = 'c0000000-0000-4000-8000-000000000211';

-- A full picnic, a picnic with a spot left, and a park day with no limit
INSERT INTO public.activities
  (
    id,
    organizer_id,
    category_id,
    title,
    starts_at,
    location_name,
    going_count,
    guest_total,
    capacity
  )
SELECT
  ('f0000000-0000-4000-8000-00000000021' || n)::uuid,
  'c0000000-0000-4000-8000-000000000211',
  'food',
  title,
  now() + n * INTERVAL '1 hour',
  'Park',
  going,
  guests,
  capacity
FROM (
  VALUES
    (1, 'Full picnic', 1, 1, 2),
    (2, 'Picnic with a spot', 1, 1, 3),
    (3, 'Park day', 1, 0, NULL)
) AS v (n, title, going, guests, capacity);

INSERT INTO public.activity_tags
  (activity_id, tag_id)
VALUES
  ('f0000000-0000-4000-8000-000000000211', 'free'),
  ('f0000000-0000-4000-8000-000000000212', 'free'),
  ('f0000000-0000-4000-8000-000000000212', 'family-friendly'),
  ('f0000000-0000-4000-8000-000000000213', 'family-friendly');

SET LOCAL ROLE authenticated;

SELECT set_config(
  'request.jwt.claims',
  '{"sub": "c0000000-0000-4000-8000-000000000211", "email": "mo@byui.edu"}',
  TRUE
);

-- The feed
SELECT results_eq(
  'select title from public.get_feed(has_spots => true)',
  $$values ('Picnic with a spot'), ('Park day')$$,
  'has spots leaves out a full activity, and counts guests'
);

SELECT results_eq(
  $$select title from public.get_feed(tag_ids => '{free}')$$,
  $$values ('Full picnic'), ('Picnic with a spot')$$,
  'a tag keeps to activities that have it'
);

SELECT results_eq(
  $$select title from public.get_feed(tag_ids => '{free, family-friendly}')$$,
  $$values ('Picnic with a spot')$$,
  'and each tag asked for must be there'
);

SELECT results_eq(
  $$select title from public.get_feed(has_spots => true, tag_ids => '{free}')$$,
  $$values ('Picnic with a spot')$$,
  'the filters combine'
);

SELECT results_eq(
  $$select count(*) from public.get_feed(tag_ids => '{}')$$,
  $$values (3::bigint)$$,
  'no tags is no filter'
);

SELECT results_eq(
  $$select title from public.get_feed(tag_ids => '{free, pizza}')$$,
  $$values ('Full picnic'), ('Picnic with a spot')$$,
  'and a tag that isn''t offered is left out'
);

-- Search
SELECT results_eq(
  $$select title from public.search_activities('picnic', has_spots => true)$$,
  $$values ('Picnic with a spot')$$,
  'search has the same filters'
);

SELECT results_eq(
  $$select title from public.search_activities('park', tag_ids => '{family-friendly}')$$,
  $$values ('Picnic with a spot'), ('Park day')$$,
  'with tags too'
);

SELECT *
FROM finish();

ROLLBACK;
