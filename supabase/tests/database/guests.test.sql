-- Bringing guests (RSVP-06). Run with `npm run db:test`.
BEGIN;

CREATE EXTENSION IF NOT EXISTS pgtap WITH SCHEMA extensions;

SELECT plan(11);

-- Gil organizes a picnic for 6 that welcomes up to 2 guests each, and a game that doesn't. Ann and
-- Bo answer.
INSERT INTO auth.users
  (id, email, raw_user_meta_data)
SELECT
  ('c0000000-0000-4000-8000-00000000024' || n)::uuid,
  name || '@byui.edu',
  jsonb_build_object('full_name', name)
FROM (
  VALUES
    (1, 'gil'),
    (2, 'ann'),
    (3, 'bo')
) AS v (n, name);

UPDATE public.profiles
SET
  guidelines_version = 1,
  guidelines_accepted_at = now()
WHERE id::text LIKE 'c0000000-0000-4000-8000-00000000024_';

INSERT INTO public.activities
  (
    id,
    organizer_id,
    category_id,
    title,
    starts_at,
    location_name,
    going_count,
    capacity,
    guests_allowed,
    max_guests_per_rsvp
  )
VALUES
  (
    'f0000000-0000-4000-8000-000000000241',
    'c0000000-0000-4000-8000-000000000241',
    'food',
    'Picnic',
    now() + INTERVAL '1 day',
    'Park',
    1,
    6,
    TRUE,
    2
  ),
  (
    'f0000000-0000-4000-8000-000000000242',
    'c0000000-0000-4000-8000-000000000241',
    'games',
    'Game',
    now() + INTERVAL '1 day',
    'Here',
    1,
    NULL,
    FALSE,
    5
  );

SET LOCAL ROLE authenticated;

-- Answers as Ann (2) or Bo (3), returning the activity's going count and guest total.
CREATE FUNCTION pg_temp.answer(member text, activity text, status text, guests INTEGER)
RETURNS text
LANGUAGE sql
AS $$
  SELECT set_config(
    'request.jwt.claims',
    json_build_object(
      'sub',
      'c0000000-0000-4000-8000-00000000024' || member,
      'email',
      member || '@byui.edu'
    )::text,
    TRUE
  );
  SELECT public.rsvp(('f0000000-0000-4000-8000-00000000024' || activity)::uuid, status, guests);
  SELECT going_count || ' going, ' || guest_total || ' guests'
  FROM public.activities
  WHERE id = ('f0000000-0000-4000-8000-00000000024' || activity)::uuid;
$$;

SELECT results_eq(
  $$select pg_temp.answer('2', '1', 'going', 1)$$,
  $$values ('2 going, 1 guests')$$,
  'a member goes with a guest'
);

SELECT results_eq(
  $$select pg_temp.answer('2', '1', 'going', NULL)$$,
  $$values ('2 going, 1 guests')$$,
  'and keeps them when they say I''m in again'
);

SELECT throws_ok(
  $$select pg_temp.answer('2', '1', 'going', 3)$$,
  '22023',
  'INVALID_GUESTS',
  'up to the number the organizer allows'
);

SELECT results_eq(
  $$select pg_temp.answer('3', '1', 'going', 2)$$,
  $$values ('3 going, 3 guests')$$,
  'guests count toward the capacity, which these fill'
);

SELECT throws_ok(
  $$select pg_temp.answer('2', '1', 'going', 2)$$,
  '22023',
  'ACTIVITY_FULL',
  'so nobody can bring more'
);

SELECT results_eq(
  $$select pg_temp.answer('3', '1', 'going', 1)$$,
  $$values ('3 going, 2 guests')$$,
  'but anyone can bring fewer'
);

SELECT results_eq(
  $$select pg_temp.answer('2', '1', 'maybe', NULL)$$,
  $$values ('2 going, 1 guests')$$,
  'a maybe brings no guests'
);

SELECT results_eq(
  $$select guest_count from public.rsvps where user_id = auth.uid()$$,
  $$values (0)$$,
  'so theirs go'
);

SELECT throws_ok(
  $$select pg_temp.answer('2', '2', 'going', 1)$$,
  '22023',
  'INVALID_GUESTS',
  'no guests unless the organizer welcomes them'
);

SELECT results_eq(
  $$select pg_temp.answer('2', '2', 'going', 0)$$,
  $$values ('2 going, 0 guests')$$,
  'though going alone is fine'
);

SELECT throws_ok(
  $$select pg_temp.answer('3', '1', 'going', -1)$$,
  '22023',
  'INVALID_GUESTS',
  'and there''s no negative number of guests'
);

SELECT *
FROM finish();

ROLLBACK;
