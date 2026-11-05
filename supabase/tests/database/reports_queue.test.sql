-- The moderators' reports queue (MOD-02). Run with `npm run db:test`.
BEGIN;

CREATE EXTENSION IF NOT EXISTS pgtap WITH SCHEMA extensions;

SELECT plan(17);

-- Mo moderates, Ada is an admin, Max was a moderator and is suspended, and Rita reports Otto.
INSERT INTO auth.users
  (id, email, raw_user_meta_data)
VALUES
  (
    'c0000000-0000-4000-8000-000000000091',
    'mo.moderator@byui.edu',
    '{"full_name": "Mo Moderator"}'
  ),
  ('c0000000-0000-4000-8000-000000000092', 'ada.admin@byui.edu', '{"full_name": "Ada Admin"}'),
  ('c0000000-0000-4000-8000-000000000093', 'max.paused@byui.edu', '{"full_name": "Max Paused"}'),
  (
    'c0000000-0000-4000-8000-000000000094',
    'rita.reporter@byui.edu',
    '{"full_name": "Rita Reporter"}'
  ),
  (
    'c0000000-0000-4000-8000-000000000095',
    'otto.organizer@byui.edu',
    '{"full_name": "Otto Organizer"}'
  );

UPDATE public.profiles
SET
  guidelines_version = 1,
  guidelines_accepted_at = now(),
  role = CASE id
    WHEN 'c0000000-0000-4000-8000-000000000092' THEN 'admin'
    WHEN 'c0000000-0000-4000-8000-000000000094' THEN 'member'
    WHEN 'c0000000-0000-4000-8000-000000000095' THEN 'member'
    ELSE 'moderator'
  END,
  status = CASE id
    WHEN 'c0000000-0000-4000-8000-000000000093' THEN 'suspended'
    ELSE 'active'
  END
WHERE id::text LIKE 'c0000000-0000-4000-8000-00000000009_';

INSERT INTO public.reports
  (id, reporter_id, target_type, target_id, reason, note)
VALUES
  (
    'e0000000-0000-4000-8000-000000000091',
    'c0000000-0000-4000-8000-000000000094',
    'activity',
    'f0000000-0000-4000-8000-000000000091',
    'spam',
    'Selling tickets'
  ),
  (
    'e0000000-0000-4000-8000-000000000092',
    'c0000000-0000-4000-8000-000000000094',
    'profile',
    'c0000000-0000-4000-8000-000000000095',
    'unsafe',
    NULL
  );

SET LOCAL ROLE authenticated;

-- Who's a moderator
SELECT set_config(
  'request.jwt.claims',
  '{"sub": "c0000000-0000-4000-8000-000000000091", "email": "mo.moderator@byui.edu"}',
  TRUE
);

SELECT ok(private.is_moderator(), 'an active moderator is a moderator');

SELECT results_eq(
  'select id from public.reports order by id',
  $$values
    ('e0000000-0000-4000-8000-000000000091'::uuid),
    ('e0000000-0000-4000-8000-000000000092'::uuid)$$,
  'and reads every report'
);

-- Dismissing
SELECT lives_ok(
  $$select public.dismiss_report('e0000000-0000-4000-8000-000000000091', '  Not a sale  ')$$,
  'a moderator dismisses a report'
);

SELECT results_eq(
  $$select status, resolved_by, resolution_note, resolved_at = now()
  from public.reports where id = 'e0000000-0000-4000-8000-000000000091'$$,
  $$values ('dismissed'::text, 'c0000000-0000-4000-8000-000000000091'::uuid, 'Not a sale'::text, true)$$,
  'it says who dismissed it, when and why'
);

SELECT throws_ok(
  $$select public.dismiss_report('e0000000-0000-4000-8000-000000000091', 'Again')$$,
  'P0002',
  'REPORT_NOT_OPEN',
  'a report is dismissed once'
);

SELECT throws_ok(
  $$select public.dismiss_report('e0000000-0000-4000-8000-0000000000ff', 'Gone')$$,
  'P0002',
  'REPORT_NOT_OPEN',
  'a report that doesn''t exist can''t be dismissed'
);

SELECT throws_ok(
  $$select public.dismiss_report('e0000000-0000-4000-8000-000000000092', ' ')$$,
  '22023',
  'REASON_REQUIRED',
  'dismissing needs a reason'
);

SELECT throws_ok(
  $$select public.dismiss_report('e0000000-0000-4000-8000-000000000092', repeat('a', 501))$$,
  '23514',
  NULL,
  'of 500 characters at most'
);

SELECT set_config(
  'request.jwt.claims',
  '{"sub": "c0000000-0000-4000-8000-000000000092", "email": "ada.admin@byui.edu"}',
  TRUE
);

SELECT lives_ok(
  $$select public.dismiss_report('e0000000-0000-4000-8000-000000000092', 'Talked to them')$$,
  'an admin dismisses a report too'
);

-- Who can't
SELECT set_config(
  'request.jwt.claims',
  '{"sub": "c0000000-0000-4000-8000-000000000093", "email": "max.paused@byui.edu"}',
  TRUE
);

SELECT ok(NOT private.is_moderator(), 'a suspended moderator isn''t a moderator');

SELECT set_config(
  'request.jwt.claims',
  '{"sub": "c0000000-0000-4000-8000-000000000094", "email": "rita.reporter@byui.edu"}',
  TRUE
);

SELECT ok(NOT private.is_moderator(), 'a member isn''t a moderator');

SELECT throws_ok(
  $$select public.dismiss_report('e0000000-0000-4000-8000-000000000092', 'Mine')$$,
  '42501',
  'NOT_MODERATOR',
  'and can''t dismiss a report'
);

SELECT throws_ok(
  $$update public.reports set status = 'dismissed'$$,
  '42501',
  NULL,
  'nor change one directly'
);

SELECT set_config(
  'request.jwt.claims',
  '{"sub": "c0000000-0000-4000-8000-000000000095", "email": "otto.organizer@byui.edu"}',
  TRUE
);

SELECT is_empty('select 1 from public.reports', 'the member reported still can''t see the reports');

-- The audit log, which only the owner reads
RESET ROLE;

SELECT results_eq(
  $$select actor_id, action, target_type, target_id, reason, metadata
  from private.audit_log where target_id = 'e0000000-0000-4000-8000-000000000091'$$,
  $$values (
    'c0000000-0000-4000-8000-000000000091'::uuid,
    'dismiss_report'::text,
    'report'::text,
    'e0000000-0000-4000-8000-000000000091'::uuid,
    'Not a sale'::text,
    '{"target_type": "activity", "target_id": "f0000000-0000-4000-8000-000000000091"}'::jsonb
  )$$,
  'each dismissal writes an audit row, with what was reported'
);

SELECT throws_ok(
  $$insert into public.reports (reporter_id, target_type, target_id, reason, resolved_at)
  values (null, 'activity', gen_random_uuid(), 'spam', now())$$,
  '23514',
  NULL,
  'an open report hasn''t been resolved'
);

SELECT function_privs_are(
  'public',
  'dismiss_report',
  ARRAY['uuid', 'text'],
  'anon',
  ARRAY[]::text[],
  'visitors can''t dismiss reports'
);

SELECT *
FROM finish();

ROLLBACK;
