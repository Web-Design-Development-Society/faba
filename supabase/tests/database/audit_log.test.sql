-- The audit log (MOD-05). Run with `npm run db:test`.
BEGIN;

CREATE EXTENSION IF NOT EXISTS pgtap WITH SCHEMA extensions;

SELECT plan(17);

-- Mo moderates. The tests run as the database owner, as SECURITY DEFINER functions do.
INSERT INTO auth.users
  (id, email, raw_user_meta_data)
VALUES
  (
    'c0000000-0000-4000-8000-000000000071',
    'mo.moderator@byui.edu',
    '{"full_name": "Mo Moderator"}'
  );

SELECT set_config(
  'request.jwt.claims',
  '{"sub": "c0000000-0000-4000-8000-000000000071", "email": "mo.moderator@byui.edu"}',
  TRUE
);

-- Writing rows
SELECT lives_ok(
  $$select private.audit(
    'hide',
    'activity',
    'd0000000-0000-4000-8000-000000000071',
    '  Selling tickets  ',
    '{"report_id": "e0000000-0000-4000-8000-000000000071"}'
  )$$,
  'a moderation function writes an audit row'
);

SELECT results_eq(
  $$select actor_id, action, target_type, target_id, reason, metadata, created_at = now()
  from private.audit_log where action = 'hide'$$,
  $$values (
    'c0000000-0000-4000-8000-000000000071'::uuid,
    'hide'::text,
    'activity'::text,
    'd0000000-0000-4000-8000-000000000071'::uuid,
    'Selling tickets'::text,
    '{"report_id": "e0000000-0000-4000-8000-000000000071"}'::jsonb,
    true
  )$$,
  'with the actor, action, target, reason and time'
);

SELECT private.audit('delete_account', 'profile', 'c0000000-0000-4000-8000-000000000072', ' ');

SELECT results_eq(
  $$select reason, metadata from private.audit_log where action = 'delete_account'$$,
  $$values (null::text, '{}'::jsonb)$$,
  'the reason and details are optional'
);

-- A runbook in the dashboard, where nobody is signed in
SELECT set_config('request.jwt.claims', '', TRUE);

SELECT private.audit(
  'data_fix',
  'profile',
  'c0000000-0000-4000-8000-000000000072',
  'Moved activities to a new account'
);

SELECT extensions.is(
  (SELECT actor_id FROM private.audit_log WHERE action = 'data_fix'),
  NULL,
  'an admin data fix in the dashboard has no actor'
);

-- The rules for a row
SELECT throws_ok(
  $$select private.audit('edit', 'activity', 'd0000000-0000-4000-8000-000000000071')$$,
  '23514',
  NULL,
  'the action is one of the listed ones'
);

SELECT throws_ok(
  $$select private.audit('hide', 'category', 'd0000000-0000-4000-8000-000000000071')$$,
  '23514',
  NULL,
  'and so is the target type'
);

SELECT throws_ok(
  $$select private.audit('hide', 'activity', 'd0000000-0000-4000-8000-000000000071',
    repeat('a', 501))$$,
  '23514',
  NULL,
  'a reason has 500 characters at most'
);

-- Append-only, even for the owner
SELECT throws_ok(
  $$update private.audit_log set reason = 'Nothing happened' where action = 'hide'$$,
  '42501',
  'AUDIT_LOG_APPEND_ONLY',
  'nobody can change a row'
);

SELECT throws_ok(
  $$delete from private.audit_log where action = 'hide'$$,
  '42501',
  'AUDIT_LOG_APPEND_ONLY',
  'or delete one'
);

INSERT INTO private.audit_log
  (action, target_type, target_id, created_at)
VALUES
  ('suspend', 'profile', 'c0000000-0000-4000-8000-000000000072', now() - INTERVAL '3 years 1 day');

SELECT lives_ok(
  $$delete from private.audit_log where action = 'suspend'$$,
  'rows older than the 3 years they''re kept can be deleted, for the retention job'
);

-- Nobody else can read or write it
SELECT ok(
  (SELECT relrowsecurity FROM pg_class WHERE oid = 'private.audit_log'::regclass),
  'the audit log has Row Level Security enabled'
);

SELECT table_privs_are(
  'private',
  'audit_log',
  'anon',
  ARRAY[]::text[],
  'visitors have no privileges on the audit log'
);

SELECT table_privs_are(
  'private',
  'audit_log',
  'authenticated',
  ARRAY[]::text[],
  'nor do signed-in members'
);

SELECT table_privs_are(
  'private',
  'audit_log',
  'service_role',
  ARRAY[]::text[],
  'nor does the secret key'
);

SELECT ok(
  NOT has_function_privilege('anon', 'private.audit(text, text, uuid, text, jsonb)', 'EXECUTE')
  AND NOT has_function_privilege(
    'authenticated',
    'private.audit(text, text, uuid, text, jsonb)',
    'EXECUTE'
  )
  AND NOT has_function_privilege(
    'service_role',
    'private.audit(text, text, uuid, text, jsonb)',
    'EXECUTE'
  ),
  'only the owner can call private.audit()'
);

SET LOCAL ROLE authenticated;

SELECT set_config(
  'request.jwt.claims',
  '{"sub": "c0000000-0000-4000-8000-000000000071", "email": "mo.moderator@byui.edu"}',
  TRUE
);

SELECT throws_ok(
  $$select * from private.audit_log$$,
  '42501',
  NULL,
  'a signed-in member can''t read the audit log'
);

SELECT throws_ok(
  $$select private.audit('hide', 'activity', 'd0000000-0000-4000-8000-000000000071')$$,
  '42501',
  NULL,
  'or write to it'
);

SELECT *
FROM finish();

ROLLBACK;
