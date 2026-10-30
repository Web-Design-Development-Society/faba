-- The before-user-created hook creates only byui.edu accounts (ADR-005). The email cases come from
-- design document section 12.5. Run with `npm run db:test`.
BEGIN;

CREATE EXTENSION IF NOT EXISTS pgtap WITH SCHEMA extensions;

SELECT plan(10);

-- Allowed
SELECT extensions.is(
  private.before_user_created('{"user": {"email": "a@byui.edu"}}'),
  '{}'::jsonb,
  'a@byui.edu is allowed'
);

SELECT extensions.is(
  private.before_user_created('{"user": {"email": "A@BYUI.EDU"}}'),
  '{}'::jsonb,
  'the domain check ignores case'
);

-- Rejected with a 403
SELECT extensions.is(
  private.before_user_created('{"user": {"email": "a@student.byui.edu"}}') #>> '{error,http_code}',
  '403',
  'a byui.edu subdomain is rejected'
);

SELECT extensions.is(
  private.before_user_created('{"user": {"email": "a@byui.edu.evil.com"}}') #>> '{error,http_code}',
  '403',
  'a lookalike domain is rejected'
);

SELECT extensions.is(
  private.before_user_created('{"user": {"email": "a@gmail.com"}}') #>> '{error,http_code}',
  '403',
  'a personal Gmail account is rejected'
);

SELECT extensions.is(
  private.before_user_created('{"user": {"email": ""}}') #>> '{error,http_code}',
  '403',
  'an empty email is rejected'
);

SELECT extensions.is(
  private.before_user_created('{"user": {}}') #>> '{error,http_code}',
  '403',
  'a missing email is rejected'
);

-- Only Supabase Auth can call the hook.
SELECT ok(
  has_function_privilege('supabase_auth_admin', 'private.before_user_created(jsonb)', 'execute'),
  'Supabase Auth can call the hook'
);

SELECT ok(
  NOT has_function_privilege('authenticated', 'private.before_user_created(jsonb)', 'execute'),
  'signed-in users can''t call the hook'
);

SELECT ok(
  NOT has_function_privilege('anon', 'private.before_user_created(jsonb)', 'execute'),
  'signed-out visitors can''t call the hook'
);

SELECT *
FROM finish();

ROLLBACK;
