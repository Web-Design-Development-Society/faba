-- Keeping maybe_count right when accounts go or move (RSVP-05). Run with `npm run db:test`.
BEGIN;

CREATE EXTENSION IF NOT EXISTS pgtap WITH SCHEMA extensions;

SELECT plan(4);

-- Ola organizes. Max is a maybe to both of her activities, and leaves. Old Ann is a maybe to
-- both too, and moves to New Ann, who has already said going to the second.
INSERT INTO auth.users
  (id, email, raw_user_meta_data)
SELECT
  ('c0000000-0000-4000-8000-00000000023' || n)::uuid,
  name || '@byui.edu',
  jsonb_build_object('full_name', name)
FROM (
  VALUES
    (1, 'ola'),
    (2, 'max'),
    (3, 'oldann'),
    (4, 'newann')
) AS v (n, name);

UPDATE public.profiles
SET
  guidelines_version = 1,
  guidelines_accepted_at = now()
WHERE id::text LIKE 'c0000000-0000-4000-8000-00000000023_';

INSERT INTO public.activities
  (id, organizer_id, category_id, title, starts_at, location_name, going_count, maybe_count)
VALUES
  (
    'f0000000-0000-4000-8000-000000000231',
    'c0000000-0000-4000-8000-000000000231',
    'games',
    'Board games',
    now() + INTERVAL '1 day',
    'Here',
    1,
    2
  ),
  (
    'f0000000-0000-4000-8000-000000000232',
    'c0000000-0000-4000-8000-000000000231',
    'games',
    'Puzzle night',
    now() + INTERVAL '2 days',
    'Here',
    2,
    2
  );

INSERT INTO public.rsvps
  (activity_id, user_id, status)
SELECT
  ('f0000000-0000-4000-8000-00000000023' || activity)::uuid,
  ('c0000000-0000-4000-8000-00000000023' || member)::uuid,
  status
FROM (
  VALUES
    ('1', '1', 'going'),
    ('1', '2', 'maybe'),
    ('1', '3', 'maybe'),
    ('2', '1', 'going'),
    ('2', '2', 'maybe'),
    ('2', '3', 'maybe'),
    ('2', '4', 'going')
) AS v (activity, member, status);

-- Max deletes his account.
SET LOCAL ROLE authenticated;

SELECT set_config(
  'request.jwt.claims',
  '{"sub": "c0000000-0000-4000-8000-000000000232", "email": "max@byui.edu"}',
  TRUE
);

SELECT lives_ok('select public.delete_my_account()', 'a maybe deletes their account');

RESET ROLE;

SELECT results_eq(
  $$select going_count, maybe_count from public.activities
  where id::text like 'f0000000-0000-4000-8000-00000000023_' order by id$$,
  $$values (1, 1), (2, 1)$$,
  'and is taken off each maybe count'
);

-- An admin moves Old Ann to New Ann.
SELECT lives_ok(
  $$select private.transfer_account(
    'c0000000-0000-4000-8000-000000000233',
    'c0000000-0000-4000-8000-000000000234',
    'New Google account'
  )$$,
  'an admin moves a maybe to their new account'
);

SELECT results_eq(
  $$select going_count, maybe_count from public.activities
  where id::text like 'f0000000-0000-4000-8000-00000000023_' order by id$$,
  $$values (1, 1), (2, 0)$$,
  'which keeps the maybe it moves, and drops the one the new account had answered'
);

SELECT *
FROM finish();

ROLLBACK;
