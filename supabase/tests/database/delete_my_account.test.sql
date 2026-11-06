-- Deleting my account (PROF-05). Run with `npm run db:test`.
BEGIN;

CREATE EXTENSION IF NOT EXISTS pgtap WITH SCHEMA extensions;

SELECT plan(11);

-- Dee deletes her account. Gwen stays.
INSERT INTO auth.users
  (id, email, raw_user_meta_data)
VALUES
  ('c0000000-0000-4000-8000-0000000000d1', 'dee.leaving@byui.edu', '{"full_name": "Dee Leaving"}'),
  ('c0000000-0000-4000-8000-0000000000d2', 'gwen.going@byui.edu', '{"full_name": "Gwen Going"}');

UPDATE public.profiles
SET
  guidelines_version = 1,
  guidelines_accepted_at = now()
WHERE id::text LIKE 'c0000000-0000-4000-8000-0000000000d_';

-- Dee's upcoming, hidden and past activities, and Gwen's game night and hike.
INSERT INTO public.activities
  (id, organizer_id, category_id, title, starts_at, location_name, going_count, hidden_at)
SELECT
  ('f0000000-0000-4000-8000-0000000000d' || n)::uuid,
  ('c0000000-0000-4000-8000-0000000000d' || organizer)::uuid,
  'games',
  title,
  now() + starts,
  'Here',
  going,
  hidden
FROM (
  VALUES
    (1, 1, 'Upcoming', INTERVAL '1 day', 2, NULL::timestamptz),
    (2, 1, 'Hidden', INTERVAL '1 day', 1, now()),
    (3, 1, 'Past', INTERVAL '-2 days', 1, NULL),
    (4, 2, 'Game night', INTERVAL '1 day', 2, NULL),
    (5, 2, 'Hike', INTERVAL '1 day', 1, NULL)
) AS v (n, organizer, title, starts, going, hidden);

INSERT INTO public.rsvps
  (activity_id, user_id, status)
SELECT
  ('f0000000-0000-4000-8000-0000000000d' || a)::uuid,
  ('c0000000-0000-4000-8000-0000000000d' || u)::uuid,
  status
FROM (
  VALUES
    (1, 1, 'going'),
    (1, 2, 'going'),
    (2, 1, 'going'),
    (3, 1, 'going'),
    (4, 2, 'going'),
    (4, 1, 'going'),
    (5, 2, 'going'),
    (5, 1, 'not_going')
) AS v (a, u, status);

SET LOCAL ROLE authenticated;

SELECT set_config(
  'request.jwt.claims',
  '{"sub": "c0000000-0000-4000-8000-0000000000d1", "email": "dee.leaving@byui.edu"}',
  TRUE
);

SELECT lives_ok('select public.delete_my_account()', 'a member prepares to delete their account');

RESET ROLE;

SELECT results_eq(
  $$select title, status, cancel_reason, going_count from public.activities
  where id::text like 'f0000000-0000-4000-8000-0000000000d_' order by id$$,
  $$values
    ('Upcoming'::text, 'cancelled'::text, 'Its organizer left FABA.'::text, 1),
    ('Hidden'::text, 'cancelled'::text, 'Its organizer left FABA.'::text, 0),
    ('Past'::text, 'published'::text, null::text, 0),
    ('Game night'::text, 'published'::text, null::text, 1),
    ('Hike'::text, 'published'::text, null::text, 1)$$,
  'their upcoming activities are cancelled, past ones stay, and going counts drop'
);

SELECT is_empty(
  $$select 1 from public.rsvps where user_id = 'c0000000-0000-4000-8000-0000000000d1'$$,
  'their RSVPs are removed'
);

SELECT results_eq(
  $$select count(*) from public.rsvps where user_id = 'c0000000-0000-4000-8000-0000000000d2'$$,
  $$values (3::bigint)$$,
  'and other members'' stay'
);

SELECT results_eq(
  $$select actor_id, target_type, target_id, reason, metadata from private.audit_log
  where action = 'delete_account' and target_id = 'c0000000-0000-4000-8000-0000000000d1'$$,
  $$values (
    'c0000000-0000-4000-8000-0000000000d1'::uuid,
    'profile'::text,
    'c0000000-0000-4000-8000-0000000000d1'::uuid,
    null::text,
    '{"activities_cancelled": 2, "rsvps_removed": 5}'::jsonb
  )$$,
  'the audit row keeps their ID and counts, and nothing personal'
);

-- Running it again, as the Worker does after a failed deletion
SET LOCAL ROLE authenticated;

SELECT lives_ok('select public.delete_my_account()', 'it can run again');

RESET ROLE;

SELECT results_eq(
  $$select metadata from private.audit_log
  where action = 'delete_account' and target_id = 'c0000000-0000-4000-8000-0000000000d1'
  order by id desc limit 1$$,
  $$values ('{"activities_cancelled": 0, "rsvps_removed": 0}'::jsonb)$$,
  'finding nothing more to change'
);

-- The admin API deletes the auth user, and the foreign keys do the rest
DELETE FROM auth.users
WHERE id = 'c0000000-0000-4000-8000-0000000000d1';

SELECT is_empty(
  $$select 1 from public.profiles where id = 'c0000000-0000-4000-8000-0000000000d1'
  union all
  select 1 from public.profile_private where user_id = 'c0000000-0000-4000-8000-0000000000d1'$$,
  'their profile and private profile are gone'
);

SELECT results_eq(
  $$select title, organizer_id from public.activities
  where id::text like 'f0000000-0000-4000-8000-0000000000d_' and organizer_id is null order by id$$,
  $$values ('Upcoming'::text, null::uuid), ('Hidden'::text, null::uuid), ('Past'::text, null::uuid)$$,
  'their activities stay, with no organizer, for "Former member"'
);

SET LOCAL ROLE authenticated;

SELECT throws_ok(
  'select public.delete_my_account()',
  'P0002',
  'ACCOUNT_NOT_FOUND',
  'a deleted account has nothing left to delete'
);

RESET ROLE;

SELECT function_privs_are(
  'public',
  'delete_my_account',
  ARRAY[]::text[],
  'anon',
  ARRAY[]::text[],
  'visitors can''t call it'
);

SELECT *
FROM finish();

ROLLBACK;
