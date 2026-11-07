-- Curated tags (SRCH-03). Run with `npm run db:test`.
BEGIN;

CREATE EXTENSION IF NOT EXISTS pgtap WITH SCHEMA extensions;

SELECT plan(13);

-- Tia organizes, and Max is a member.
INSERT INTO auth.users
  (id, email, raw_user_meta_data)
VALUES
  ('c0000000-0000-4000-8000-000000000201', 'tia@byui.edu', '{"full_name": "Tia Tagger"}'),
  ('c0000000-0000-4000-8000-000000000202', 'max@byui.edu', '{"full_name": "Max Member"}');

UPDATE public.profiles
SET
  guidelines_version = 1,
  guidelines_accepted_at = now()
WHERE id IN ('c0000000-0000-4000-8000-000000000201', 'c0000000-0000-4000-8000-000000000202');

-- Tia's picnic is coming up, her lunch has started, and her sale is hidden.
INSERT INTO public.activities
  (id, organizer_id, category_id, title, starts_at, location_name, hidden_at)
VALUES
  (
    'f0000000-0000-4000-8000-000000000201',
    'c0000000-0000-4000-8000-000000000201',
    'food',
    'Picnic',
    now() + INTERVAL '1 day',
    'Park',
    NULL
  ),
  (
    'f0000000-0000-4000-8000-000000000202',
    'c0000000-0000-4000-8000-000000000201',
    'food',
    'Lunch',
    now() - INTERVAL '1 hour',
    'Here',
    NULL
  ),
  (
    'f0000000-0000-4000-8000-000000000203',
    'c0000000-0000-4000-8000-000000000201',
    'other',
    'Ticket sale',
    now() + INTERVAL '1 day',
    'Here',
    now()
  );

INSERT INTO public.activity_tags
  (activity_id, tag_id)
VALUES
  ('f0000000-0000-4000-8000-000000000202', 'free'),
  ('f0000000-0000-4000-8000-000000000203', 'free');

SET LOCAL ROLE authenticated;

SELECT set_config(
  'request.jwt.claims',
  '{"sub": "c0000000-0000-4000-8000-000000000201", "email": "tia@byui.edu"}',
  TRUE
);

SELECT results_eq(
  'select id from public.tags order by sort_order',
  $$values ('free'), ('family-friendly'), ('beginner-friendly'), ('accessible')$$,
  'members read the curated tags'
);

-- Setting them
CREATE FUNCTION pg_temp.tags(activity text)
RETURNS text[]
LANGUAGE sql
AS $$
  SELECT array_agg(tag_id ORDER BY tag_id)
  FROM public.activity_tags
  WHERE activity_id = ('f0000000-0000-4000-8000-00000000020' || activity)::uuid;
$$;

SELECT lives_ok(
  $$select public.set_activity_tags('f0000000-0000-4000-8000-000000000201', '{free, family-friendly, free}')$$,
  'an organizer tags their activity'
);

SELECT results_eq(
  $$select pg_temp.tags('1')$$,
  $$values ('{family-friendly,free}'::text[])$$,
  'once each'
);

SELECT lives_ok(
  $$select public.set_activity_tags('f0000000-0000-4000-8000-000000000201', '{beginner-friendly}')$$,
  'and can change them'
);

SELECT results_eq(
  $$select pg_temp.tags('1')$$,
  $$values ('{beginner-friendly}'::text[])$$,
  'which replaces the ones it had'
);

SELECT throws_ok(
  $$select public.set_activity_tags(
    'f0000000-0000-4000-8000-000000000201',
    '{free, family-friendly, beginner-friendly, accessible}'
  )$$,
  '22023',
  'TOO_MANY_TAGS',
  'up to 3'
);

SELECT throws_ok(
  $$select public.set_activity_tags('f0000000-0000-4000-8000-000000000201', '{pizza}')$$,
  '22023',
  'INVALID_TAG',
  'from the list'
);

SELECT throws_ok(
  $$select public.set_activity_tags('f0000000-0000-4000-8000-000000000202', '{accessible}')$$,
  '22023',
  'ACTIVITY_STARTED',
  'until it starts'
);

SELECT lives_ok(
  $$select public.set_activity_tags('f0000000-0000-4000-8000-000000000202', '{free}')$$,
  'though saving the same tags after then changes nothing'
);

-- A tag that's no longer offered
RESET ROLE;

UPDATE public.tags
SET is_active = FALSE
WHERE id = 'beginner-friendly';

SET LOCAL ROLE authenticated;

SELECT lives_ok(
  $$select public.set_activity_tags('f0000000-0000-4000-8000-000000000201', '{beginner-friendly, free}')$$,
  'an activity keeps a tag that''s no longer offered'
);

-- Other members
SELECT set_config(
  'request.jwt.claims',
  '{"sub": "c0000000-0000-4000-8000-000000000202", "email": "max@byui.edu"}',
  TRUE
);

SELECT throws_ok(
  $$select public.set_activity_tags('f0000000-0000-4000-8000-000000000201', '{free}')$$,
  '42501',
  'NOT_ORGANIZER',
  'only its organizer can tag it'
);

SELECT results_eq(
  $$select activity_id, tag_id from public.activity_tags
  where activity_id::text like 'f0000000-0000-4000-8000-00000000020_' order by activity_id, tag_id$$,
  $$values
    ('f0000000-0000-4000-8000-000000000201'::uuid, 'beginner-friendly'::text),
    ('f0000000-0000-4000-8000-000000000201'::uuid, 'free'::text),
    ('f0000000-0000-4000-8000-000000000202'::uuid, 'free'::text)$$,
  'members read the tags of the activities they can read, not a hidden one''s'
);

RESET ROLE;

SELECT function_privs_are(
  'public',
  'set_activity_tags',
  ARRAY['uuid', 'text[]'],
  'anon',
  ARRAY[]::text[],
  'visitors can''t tag activities'
);

SELECT *
FROM finish();

ROLLBACK;
