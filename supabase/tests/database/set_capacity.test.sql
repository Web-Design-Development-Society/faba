-- Setting an activity's capacity (RSVP-04). Run with `npm run db:test`.
BEGIN;

CREATE EXTENSION IF NOT EXISTS pgtap WITH SCHEMA extensions;

SELECT plan(10);

INSERT INTO auth.users
  (id, email, raw_user_meta_data)
VALUES
  ('c0000000-0000-4000-8000-0000000001f1', 'cap@byui.edu', '{"full_name": "Cap Organizer"}');

UPDATE public.profiles
SET
  guidelines_version = 1,
  guidelines_accepted_at = now()
WHERE id = 'c0000000-0000-4000-8000-0000000001f1';

-- Cap's game has 3 going, and their lunch has started.
INSERT INTO public.activities
  (id, organizer_id, category_id, title, starts_at, location_name, going_count, capacity)
VALUES
  (
    'f0000000-0000-4000-8000-0000000001f1',
    'c0000000-0000-4000-8000-0000000001f1',
    'games',
    'Board games',
    now() + INTERVAL '1 day',
    'Here',
    3,
    NULL
  ),
  (
    'f0000000-0000-4000-8000-0000000001f2',
    'c0000000-0000-4000-8000-0000000001f1',
    'games',
    'Lunch',
    now() - INTERVAL '1 hour',
    'Here',
    1,
    10
  );

SET LOCAL ROLE authenticated;

SELECT set_config(
  'request.jwt.claims',
  '{"sub": "c0000000-0000-4000-8000-0000000001f1", "email": "cap@byui.edu"}',
  TRUE
);

-- Posting
CREATE FUNCTION pg_temp.post(capacity INTEGER)
RETURNS uuid
LANGUAGE sql
AS $$
  SELECT public.create_activity(
    title => 'Pickleball',
    category_id => 'sports',
    starts_at => now() + INTERVAL '2 days',
    location_name => 'Hart courts',
    capacity => capacity
  );
$$;

CREATE TEMPORARY TABLE posted AS
  SELECT pg_temp.post(8) AS with_capacity, pg_temp.post(NULL) AS without;

SELECT results_eq(
  $$select capacity from public.activities where id = (select with_capacity from posted)$$,
  $$values (8)$$,
  'an organizer can post with a capacity'
);

SELECT results_eq(
  $$select capacity from public.activities where id = (select without from posted)$$,
  $$values (NULL::integer)$$,
  'or without one'
);

SELECT throws_ok('select pg_temp.post(0)', '22023', 'INVALID_CAPACITY', 'but not of 0');

SELECT throws_ok('select pg_temp.post(501)', '22023', 'INVALID_CAPACITY', 'or over 500');

-- Editing
CREATE FUNCTION pg_temp.edit(activity text, patch jsonb)
RETURNS void
LANGUAGE sql
AS $$
  SELECT public.update_activity(
    ('f0000000-0000-4000-8000-0000000001f' || activity)::uuid,
    patch,
    (
      SELECT version
      FROM public.activities
      WHERE id = ('f0000000-0000-4000-8000-0000000001f' || activity)::uuid
    )
  );
$$;

SELECT lives_ok(
  $$select pg_temp.edit('1', '{"capacity": 2}')$$,
  'an organizer can set a capacity below the count'
);

SELECT results_eq(
  $$select capacity, going_count from public.activities
  where id = 'f0000000-0000-4000-8000-0000000001f1'$$,
  $$values (2, 3)$$,
  'and everyone going stays going'
);

SELECT lives_ok($$select pg_temp.edit('1', '{"capacity": null}')$$, 'or clear it');

SELECT results_eq(
  $$select capacity from public.activities where id = 'f0000000-0000-4000-8000-0000000001f1'$$,
  $$values (NULL::integer)$$,
  'so it has none'
);

SELECT throws_ok(
  $$select pg_temp.edit('1', '{"capacity": 501}')$$,
  '22023',
  'INVALID_CAPACITY',
  'but not over 500'
);

SELECT throws_ok(
  $$select pg_temp.edit('2', '{"capacity": 20}')$$,
  '22023',
  'ACTIVITY_STARTED',
  'nor once it has started'
);

SELECT *
FROM finish();

ROLLBACK;
