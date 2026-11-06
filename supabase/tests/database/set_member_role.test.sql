-- Appointing moderators and admins (MOD-06). Run with `npm run db:test`.
BEGIN;

CREATE EXTENSION IF NOT EXISTS pgtap WITH SCHEMA extensions;

SELECT plan(15);

-- Ada is the only admin, and Mo and Gwen are members. The seed's admins step down for the test.
INSERT INTO auth.users
  (id, email, raw_user_meta_data)
VALUES
  ('c0000000-0000-4000-8000-0000000000c1', 'ada.admin@byui.edu', '{"full_name": "Ada Admin"}'),
  ('c0000000-0000-4000-8000-0000000000c2', 'mo.member@byui.edu', '{"full_name": "Mo Member"}'),
  ('c0000000-0000-4000-8000-0000000000c3', 'gwen.going@byui.edu', '{"full_name": "Gwen Going"}');

UPDATE public.profiles
SET role = 'member'
WHERE role = 'admin';

UPDATE public.profiles
SET
  guidelines_version = 1,
  guidelines_accepted_at = now(),
  role = CASE id
    WHEN 'c0000000-0000-4000-8000-0000000000c1' THEN 'admin'
    ELSE 'member'
  END
WHERE id::text LIKE 'c0000000-0000-4000-8000-0000000000c_';

-- The dashboard, where nobody is signed in
SELECT set_config('request.jwt.claims', '', TRUE);

SELECT throws_ok(
  $$select private.set_member_role('c0000000-0000-4000-8000-0000000000c2', 'moderator', ' ')$$,
  '22023',
  'REASON_REQUIRED',
  'a role change needs a reason'
);

SELECT throws_ok(
  $$select private.set_member_role('c0000000-0000-4000-8000-0000000000ff', 'moderator', 'Joined')$$,
  'P0002',
  'MEMBER_NOT_FOUND',
  'a member who doesn''t exist has no role'
);

SELECT throws_ok(
  $$select private.set_member_role('c0000000-0000-4000-8000-0000000000c2', 'owner', 'Joined')$$,
  '23514',
  NULL,
  'the role is member, moderator or admin'
);

SELECT lives_ok(
  $$select private.set_member_role(
    'c0000000-0000-4000-8000-0000000000c2', 'moderator', ' Joined the board '
  )$$,
  'an admin makes a member a moderator'
);

SELECT throws_ok(
  $$select private.set_member_role('c0000000-0000-4000-8000-0000000000c2', 'moderator', 'Again')$$,
  '22023',
  'ROLE_UNCHANGED',
  'to a role they already have'
);

-- The role applies on Mo's next request
SET LOCAL ROLE authenticated;

SELECT set_config(
  'request.jwt.claims',
  '{"sub": "c0000000-0000-4000-8000-0000000000c2", "email": "mo.member@byui.edu"}',
  TRUE
);

SELECT ok(private.is_moderator(), 'the new moderator moderates on their next request');

SELECT results_eq(
  'select role from public.get_session_context()',
  $$values ('moderator'::text)$$,
  'and the app reads the new role'
);

SELECT throws_ok(
  $$select private.set_member_role('c0000000-0000-4000-8000-0000000000c3', 'admin', 'Me too')$$,
  '42501',
  NULL,
  'members can''t change roles'
);

RESET ROLE;

SELECT set_config('request.jwt.claims', '', TRUE);

-- At least one admin
SELECT throws_ok(
  $$select private.set_member_role('c0000000-0000-4000-8000-0000000000c1', 'member', 'Stepping down')$$,
  '22023',
  'LAST_ADMIN',
  'the last admin can''t step down'
);

SELECT lives_ok(
  $$select private.set_member_role('c0000000-0000-4000-8000-0000000000c3', 'admin', 'New chair')$$,
  'until there''s another admin'
);

SELECT lives_ok(
  $$select private.set_member_role('c0000000-0000-4000-8000-0000000000c1', 'member', 'Stepping down')$$,
  'and then they can'
);

SELECT lives_ok(
  $$select private.set_member_role('c0000000-0000-4000-8000-0000000000c2', 'member', 'Left the board')$$,
  'an admin takes away a moderator role'
);

SET LOCAL ROLE authenticated;

SELECT set_config(
  'request.jwt.claims',
  '{"sub": "c0000000-0000-4000-8000-0000000000c2", "email": "mo.member@byui.edu"}',
  TRUE
);

SELECT ok(NOT private.is_moderator(), 'which applies on their next request too');

RESET ROLE;

SELECT results_eq(
  $$select actor_id, target_id, reason, metadata from private.audit_log
  where action = 'set_role' and target_id::text like '%-0000000000c_' order by id$$,
  $$values
    (null::uuid, 'c0000000-0000-4000-8000-0000000000c2'::uuid, 'Joined the board'::text, '{"from": "member", "to": "moderator"}'::jsonb),
    (null::uuid, 'c0000000-0000-4000-8000-0000000000c3'::uuid, 'New chair'::text, '{"from": "member", "to": "admin"}'::jsonb),
    (null::uuid, 'c0000000-0000-4000-8000-0000000000c1'::uuid, 'Stepping down'::text, '{"from": "admin", "to": "member"}'::jsonb),
    (null::uuid, 'c0000000-0000-4000-8000-0000000000c2'::uuid, 'Left the board'::text, '{"from": "moderator", "to": "member"}'::jsonb)$$,
  'each change writes an audit row with the old and new role, and no actor from the dashboard'
);

SELECT ok(
  NOT has_function_privilege('anon', 'private.set_member_role(uuid, text, text)', 'EXECUTE')
  AND NOT has_function_privilege(
    'authenticated',
    'private.set_member_role(uuid, text, text)',
    'EXECUTE'
  )
  AND NOT has_function_privilege(
    'service_role',
    'private.set_member_role(uuid, text, text)',
    'EXECUTE'
  ),
  'only the database owner can change roles'
);

SELECT *
FROM finish();

ROLLBACK;
