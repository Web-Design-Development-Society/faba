-- Capacity and "Full" (RSVP-04). Run with `npm run db:test`.
BEGIN;

CREATE EXTENSION IF NOT EXISTS pgtap WITH SCHEMA extensions;

SELECT plan(12);

-- Ora organizes, and Ann, Bo and Cy RSVP.
INSERT INTO auth.users
  (id, email, raw_user_meta_data)
SELECT
  ('c0000000-0000-4000-8000-0000000001e' || n)::uuid,
  name || '@byui.edu',
  jsonb_build_object('full_name', name)
FROM (
  VALUES
    (1, 'ora'),
    (2, 'ann'),
    (3, 'bo'),
    (4, 'cy')
) AS v (n, name);

UPDATE public.profiles
SET
  guidelines_version = 1,
  guidelines_accepted_at = now()
WHERE id::text LIKE 'c0000000-0000-4000-8000-0000000001e_';

-- Ora is going to each, as create_activity() would have made her. The picnic has a guest coming.
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
  ('f0000000-0000-4000-8000-0000000001e' || n)::uuid,
  'c0000000-0000-4000-8000-0000000001e1',
  'games',
  title,
  now() + INTERVAL '1 day',
  'Here',
  1,
  guests,
  capacity
FROM (
  VALUES
    (1, 'Game for two', 0, 2),
    (2, 'Picnic for three', 1, 3),
    (3, 'Open lunch', 0, NULL)
) AS v (n, title, guests, capacity);

INSERT INTO public.rsvps
  (activity_id, user_id, status)
SELECT
  ('f0000000-0000-4000-8000-0000000001e' || n)::uuid,
  'c0000000-0000-4000-8000-0000000001e1',
  'going'
FROM generate_series(1, 3) AS n;

SET LOCAL ROLE authenticated;

-- Each of Ann, Bo and Cy says I'm in, or not, as themselves.
CREATE FUNCTION pg_temp.rsvp_as(member text, activity text, status text)
RETURNS INTEGER
LANGUAGE sql
AS $$
  SELECT set_config(
    'request.jwt.claims',
    json_build_object(
      'sub',
      'c0000000-0000-4000-8000-0000000001e' || member,
      'email',
      member || '@byui.edu'
    )::text,
    TRUE
  );
  SELECT public.rsvp(('f0000000-0000-4000-8000-0000000001e' || activity)::uuid, status);
$$;

SELECT results_eq(
  $$select pg_temp.rsvp_as('2', '1', 'going')$$,
  $$values (2)$$,
  'the last spot is taken'
);

SELECT throws_ok(
  $$select pg_temp.rsvp_as('3', '1', 'going')$$,
  '22023',
  'ACTIVITY_FULL',
  'and then it''s full'
);

SELECT results_eq(
  $$select pg_temp.rsvp_as('2', '1', 'going')$$,
  $$values (2)$$,
  'but someone going stays going'
);

SELECT results_eq(
  $$select pg_temp.rsvp_as('3', '1', 'not_going')$$,
  $$values (2)$$,
  'and anyone can say they can''t make it'
);

SELECT results_eq(
  $$select pg_temp.rsvp_as('2', '1', 'not_going')$$,
  $$values (1)$$,
  'a spot opens when someone drops out'
);

SELECT results_eq(
  $$select pg_temp.rsvp_as('3', '1', 'going')$$,
  $$values (2)$$,
  'and the next member can take it'
);

-- Guests and no capacity
SELECT results_eq(
  $$select pg_temp.rsvp_as('2', '2', 'going')$$,
  $$values (2)$$,
  'guests count toward the capacity'
);

SELECT throws_ok(
  $$select pg_temp.rsvp_as('3', '2', 'going')$$,
  '22023',
  'ACTIVITY_FULL',
  'so two going and a guest fill three spots'
);

SELECT results_eq(
  $$select pg_temp.rsvp_as('4', '3', 'going')$$,
  $$values (2)$$,
  'without a capacity'
);

SELECT results_eq(
  $$select pg_temp.rsvp_as('2', '3', 'going')$$,
  $$values (3)$$,
  'there''s no limit'
);

-- Lowering the capacity
RESET ROLE;

UPDATE public.activities
SET capacity = 1
WHERE id = 'f0000000-0000-4000-8000-0000000001e1';

SELECT results_eq(
  $$select going_count from public.activities where id = 'f0000000-0000-4000-8000-0000000001e1'$$,
  $$values (2)$$,
  'lowering the capacity below the count keeps everyone going'
);

SET LOCAL ROLE authenticated;

SELECT throws_ok(
  $$select pg_temp.rsvp_as('2', '1', 'going')$$,
  '22023',
  'ACTIVITY_FULL',
  'but nobody new can go'
);

SELECT *
FROM finish();

ROLLBACK;
