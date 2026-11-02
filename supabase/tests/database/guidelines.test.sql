-- Accepting the community guidelines on Welcome, and the session context (PROF-01). Until a
-- member accepts the current version, they aren't an active member. Run with `npm run db:test`.
BEGIN;

CREATE EXTENSION IF NOT EXISTS pgtap WITH SCHEMA extensions;

SELECT plan(16);

-- A new member, whose profile the on_auth_user_created trigger makes
INSERT INTO auth.users
  (id, email, raw_user_meta_data)
VALUES
  (
    'b0000000-0000-4000-8000-000000000001',
    'nia.newcomer@byui.edu',
    '{"full_name": "Nia Newcomer"}'
  );

SET LOCAL ROLE authenticated;

SELECT set_config(
  'request.jwt.claims',
  '{"sub": "b0000000-0000-4000-8000-000000000001", "email": "nia.newcomer@byui.edu"}',
  TRUE
);

SELECT results_eq(
  'select display_name, guidelines_ok from public.get_session_context()',
  $$values ('Nia Newcomer', false)$$,
  'a new member hasn''t accepted the guidelines'
);

SELECT ok(NOT private.is_active_member(), 'a new member isn''t an active member yet');

SELECT is_empty('select 1 from public.activities', 'a new member reads no activities yet');

SELECT throws_ok(
  $$select public.accept_guidelines(0, 'Nia Newcomer', false)$$,
  '22023',
  'GUIDELINES_CHANGED',
  'accepting an old version of the guidelines fails'
);

SELECT throws_ok(
  $$select public.accept_guidelines(1, ' N ', false)$$,
  '23514',
  NULL,
  'a display name shorter than 2 characters fails'
);

SELECT lives_ok(
  $$select public.accept_guidelines(1, '  Nia N.  ', true)$$,
  'a new member accepts the guidelines'
);

SELECT results_eq(
  'select display_name, use_initials, guidelines_ok from public.get_session_context()',
  $$values ('Nia N.', true, true)$$,
  'accepting stores the trimmed display name and the initials choice'
);

SELECT ok(private.is_active_member(), 'after accepting, they''re an active member');

SELECT isnt_empty('select 1 from public.activities', 'after accepting, they read activities');

-- The guidelines change
RESET role;

CREATE OR REPLACE FUNCTION private.guidelines_version()
RETURNS INTEGER
LANGUAGE sql
IMMUTABLE
SET search_path = ''
AS $$
  SELECT 2;
$$;

SET LOCAL ROLE authenticated;

SELECT extensions.is(
  (SELECT guidelines_ok FROM public.get_session_context()),
  FALSE,
  'when the guidelines change, members must accept them again'
);

SELECT ok(NOT private.is_active_member(), 'until then, they aren''t an active member');

-- Who can't accept
SELECT set_config(
  'request.jwt.claims',
  '{"sub": "b0000000-0000-4000-8000-000000000001", "email": "nia.newcomer@gmail.com"}',
  TRUE
);

SELECT throws_ok(
  $$select public.accept_guidelines(2, 'Nia Newcomer', false)$$,
  '42501',
  'NOT_ELIGIBLE',
  'a session whose email isn''t byui.edu can''t accept'
);

SELECT set_config(
  'request.jwt.claims',
  '{"sub": "00000000-0000-4000-8000-000000000005", "email": "suspended.test@byui.edu"}',
  TRUE
);

SELECT throws_ok(
  $$select public.accept_guidelines(2, 'Sam Suspended', false)$$,
  '42501',
  'NOT_ACTIVE',
  'a suspended member can''t accept'
);

RESET role;

SELECT ok(
  NOT has_function_privilege('anon', 'public.accept_guidelines(integer, text, boolean)', 'execute'),
  'signed-out visitors can''t accept the guidelines'
);

SELECT ok(
  NOT has_function_privilege('anon', 'public.get_session_context()', 'execute'),
  'signed-out visitors can''t read a session context'
);

SELECT ok(
  has_function_privilege(
    'authenticated',
    'public.accept_guidelines(integer, text, boolean)',
    'execute'
  ),
  'signed-in users can accept the guidelines'
);

SELECT *
FROM finish();

ROLLBACK;
