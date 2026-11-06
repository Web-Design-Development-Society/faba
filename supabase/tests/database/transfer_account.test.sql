-- Moving a member's activities and RSVPs to their new account (OPS-01). Run with
-- `npm run db:test`.
BEGIN;

CREATE EXTENSION IF NOT EXISTS pgtap WITH SCHEMA extensions;

SELECT plan(12);

-- Olive's old account (e1) and new one (e2), and Gwen.
INSERT INTO auth.users
  (id, email, raw_user_meta_data)
VALUES
  ('c0000000-0000-4000-8000-0000000000e1', 'olive.old@byui.edu', '{"full_name": "Olive Old"}'),
  ('c0000000-0000-4000-8000-0000000000e2', 'olive.new@byui.edu', '{"full_name": "Olive New"}'),
  ('c0000000-0000-4000-8000-0000000000e3', 'gwen.going@byui.edu', '{"full_name": "Gwen Going"}');

-- Olive's hike, and Gwen's game night and lunch.
INSERT INTO public.activities
  (id, organizer_id, category_id, title, starts_at, location_name, going_count)
SELECT
  ('f0000000-0000-4000-8000-0000000000e' || n)::uuid,
  ('c0000000-0000-4000-8000-0000000000e' || organizer)::uuid,
  'games',
  title,
  now() + INTERVAL '1 day',
  'Here',
  going
FROM (
  VALUES
    (1, 1, 'Hike', 2),
    (2, 3, 'Game night', 3),
    (3, 3, 'Lunch', 1)
) AS v (n, organizer, title, going);

-- Both of Olive's accounts are going to game night. Her old one can't make lunch.
INSERT INTO public.rsvps
  (activity_id, user_id, status)
SELECT
  ('f0000000-0000-4000-8000-0000000000e' || a)::uuid,
  ('c0000000-0000-4000-8000-0000000000e' || u)::uuid,
  status
FROM (
  VALUES
    (1, 1, 'going'),
    (1, 3, 'going'),
    (2, 3, 'going'),
    (2, 1, 'going'),
    (2, 2, 'going'),
    (3, 3, 'going'),
    (3, 1, 'not_going')
) AS v (a, u, status);

-- The dashboard, where nobody is signed in
SELECT set_config('request.jwt.claims', '', TRUE);

SELECT throws_ok(
  $$select private.transfer_account(
    'c0000000-0000-4000-8000-0000000000e1', 'c0000000-0000-4000-8000-0000000000e2', ' '
  )$$,
  '22023',
  'REASON_REQUIRED',
  'a transfer needs a reason'
);

SELECT throws_ok(
  $$select private.transfer_account(
    'c0000000-0000-4000-8000-0000000000e1', 'c0000000-0000-4000-8000-0000000000e1', 'Same'
  )$$,
  '22023',
  'SAME_ACCOUNT',
  'between two accounts'
);

SELECT throws_ok(
  $$select private.transfer_account(
    'c0000000-0000-4000-8000-0000000000e1', 'c0000000-0000-4000-8000-0000000000ff', 'Gone'
  )$$,
  'P0002',
  'MEMBER_NOT_FOUND',
  'that both exist'
);

SELECT lives_ok(
  $$select private.transfer_account(
    'c0000000-0000-4000-8000-0000000000e1',
    'c0000000-0000-4000-8000-0000000000e2',
    ' New Google account after a name change '
  )$$,
  'an admin moves an old account to a new one'
);

SELECT results_eq(
  $$select organizer_id from public.activities where id = 'f0000000-0000-4000-8000-0000000000e1'$$,
  $$values ('c0000000-0000-4000-8000-0000000000e2'::uuid)$$,
  'the new account organizes the old one''s activities'
);

SELECT results_eq(
  $$select a.title, r.status from public.rsvps as r join public.activities as a on a.id = r.activity_id
  where r.user_id = 'c0000000-0000-4000-8000-0000000000e2' order by a.id$$,
  $$values ('Hike'::text, 'going'::text), ('Game night'::text, 'going'::text), ('Lunch'::text, 'not_going'::text)$$,
  'and has its RSVPs, keeping its own where both answered'
);

SELECT is_empty(
  $$select 1 from public.rsvps where user_id = 'c0000000-0000-4000-8000-0000000000e1'$$,
  'the old account has no RSVPs left'
);

SELECT results_eq(
  $$select title, going_count from public.activities
  where id::text like 'f0000000-0000-4000-8000-0000000000e_' order by id$$,
  $$values ('Hike'::text, 2), ('Game night'::text, 2), ('Lunch'::text, 1)$$,
  'and nobody is counted twice'
);

SELECT results_eq(
  $$select count(*) from public.rsvps where user_id = 'c0000000-0000-4000-8000-0000000000e3'$$,
  $$values (3::bigint)$$,
  'other members'' RSVPs stay'
);

SELECT results_eq(
  $$select count(*) from public.profiles where id::text like 'c0000000-0000-4000-8000-0000000000e_'$$,
  $$values (3::bigint)$$,
  'and both profiles stay, for the admin to delete the old account'
);

SELECT results_eq(
  $$select actor_id, action, target_id, reason, metadata from private.audit_log
  where target_id = 'c0000000-0000-4000-8000-0000000000e1'$$,
  $$values (
    null::uuid,
    'data_fix'::text,
    'c0000000-0000-4000-8000-0000000000e1'::uuid,
    'New Google account after a name change'::text,
    '{"transferred_to": "c0000000-0000-4000-8000-0000000000e2", "activities": 1, "rsvps_moved": 2, "rsvps_dropped": 1}'::jsonb
  )$$,
  'the transfer writes a data_fix audit row with both IDs and the counts'
);

SELECT ok(
  NOT has_function_privilege('anon', 'private.transfer_account(uuid, uuid, text)', 'EXECUTE')
  AND NOT has_function_privilege(
    'authenticated',
    'private.transfer_account(uuid, uuid, text)',
    'EXECUTE'
  )
  AND NOT has_function_privilege(
    'service_role',
    'private.transfer_account(uuid, uuid, text)',
    'EXECUTE'
  ),
  'only the database owner can transfer an account'
);

SELECT *
FROM finish();

ROLLBACK;
