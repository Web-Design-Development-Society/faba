-- "Maybe" (RSVP-05). Run with `npm run db:test`.
BEGIN;

CREATE EXTENSION IF NOT EXISTS pgtap WITH SCHEMA extensions;

SELECT plan(11);

-- Oz organizes a game for two, and Mia and Ned answer.
INSERT INTO auth.users
  (id, email, raw_user_meta_data)
SELECT
  ('c0000000-0000-4000-8000-00000000022' || n)::uuid,
  name || '@byui.edu',
  jsonb_build_object('full_name', name)
FROM (
  VALUES
    (1, 'oz'),
    (2, 'mia'),
    (3, 'ned')
) AS v (n, name);

UPDATE public.profiles
SET
  guidelines_version = 1,
  guidelines_accepted_at = now()
WHERE id::text LIKE 'c0000000-0000-4000-8000-00000000022_';

INSERT INTO public.activities
  (id, organizer_id, category_id, title, starts_at, location_name, going_count, capacity)
VALUES
  (
    'f0000000-0000-4000-8000-000000000221',
    'c0000000-0000-4000-8000-000000000221',
    'games',
    'Game for two',
    now() + INTERVAL '1 day',
    'Here',
    1,
    2
  );

INSERT INTO public.rsvps
  (activity_id, user_id, status)
VALUES
  ('f0000000-0000-4000-8000-000000000221', 'c0000000-0000-4000-8000-000000000221', 'going');

SET LOCAL ROLE authenticated;

-- Answers as Oz (1), Mia (2) or Ned (3), returning the going and maybe counts.
CREATE FUNCTION pg_temp.answer(member text, status text)
RETURNS text
LANGUAGE sql
AS $$
  SELECT set_config(
    'request.jwt.claims',
    json_build_object(
      'sub',
      'c0000000-0000-4000-8000-00000000022' || member,
      'email',
      member || '@byui.edu'
    )::text,
    TRUE
  );
  SELECT public.rsvp('f0000000-0000-4000-8000-000000000221', status);
  SELECT going_count || ' going, ' || maybe_count || ' maybe'
  FROM public.activities
  WHERE id = 'f0000000-0000-4000-8000-000000000221';
$$;

SELECT results_eq(
  $$select pg_temp.answer('2', 'maybe')$$,
  $$values ('1 going, 1 maybe')$$,
  'a member says maybe, which doesn''t take a spot'
);

SELECT results_eq(
  $$select pg_temp.answer('2', 'going')$$,
  $$values ('2 going, 0 maybe')$$,
  'then going, which does'
);

SELECT results_eq(
  $$select pg_temp.answer('3', 'maybe')$$,
  $$values ('2 going, 1 maybe')$$,
  'a member can say maybe when it''s full'
);

SELECT throws_ok(
  $$select pg_temp.answer('3', 'going')$$,
  '22023',
  'ACTIVITY_FULL',
  'but not going'
);

SELECT results_eq(
  $$select pg_temp.answer('2', 'maybe')$$,
  $$values ('1 going, 2 maybe')$$,
  'going to maybe gives the spot back'
);

SELECT results_eq(
  $$select pg_temp.answer('2', 'not_going')$$,
  $$values ('1 going, 1 maybe')$$,
  'and maybe to can''t make it counts them out'
);

SELECT throws_ok(
  $$select pg_temp.answer('1', 'maybe')$$,
  '22023',
  'ORGANIZER_GOING',
  'the organizer stays going'
);

SELECT throws_ok(
  $$select pg_temp.answer('3', 'perhaps')$$,
  '22023',
  'INVALID_STATUS',
  'and there''s no other answer'
);

-- Who sees a maybe: Ned's
SELECT set_config(
  'request.jwt.claims',
  '{"sub": "c0000000-0000-4000-8000-000000000223", "email": "ned@byui.edu"}',
  TRUE
);

SELECT results_eq(
  $$select status from public.rsvps where user_id = auth.uid()$$,
  $$values ('maybe')$$,
  'a member sees their own maybe'
);

SELECT set_config(
  'request.jwt.claims',
  '{"sub": "c0000000-0000-4000-8000-000000000222", "email": "mia@byui.edu"}',
  TRUE
);

SELECT is_empty($$select from public.rsvps where status = 'maybe'$$, 'but other members don''t');

SELECT set_config(
  'request.jwt.claims',
  '{"sub": "c0000000-0000-4000-8000-000000000221", "email": "oz@byui.edu"}',
  TRUE
);

SELECT results_eq(
  $$select user_id from public.rsvps where status = 'maybe'$$,
  $$values ('c0000000-0000-4000-8000-000000000223'::uuid)$$,
  'while the organizer sees who'
);

SELECT *
FROM finish();

ROLLBACK;
