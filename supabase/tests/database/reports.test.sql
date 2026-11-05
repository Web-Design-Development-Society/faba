-- Reporting an activity or a member (MOD-01). Run with `npm run db:test`.
BEGIN;

CREATE EXTENSION IF NOT EXISTS pgtap WITH SCHEMA extensions;

SELECT plan(22);

-- Rita reports, Otto organizes, and Sue is suspended.
INSERT INTO auth.users
  (id, email, raw_user_meta_data)
VALUES
  (
    'c0000000-0000-4000-8000-000000000081',
    'rita.reporter@byui.edu',
    '{"full_name": "Rita Reporter"}'
  ),
  (
    'c0000000-0000-4000-8000-000000000082',
    'otto.organizer@byui.edu',
    '{"full_name": "Otto Organizer"}'
  ),
  (
    'c0000000-0000-4000-8000-000000000083',
    'sue.suspended@byui.edu',
    '{"full_name": "Sue Suspended"}'
  );

UPDATE public.profiles
SET
  guidelines_version = 1,
  guidelines_accepted_at = now(),
  status = CASE id
    WHEN 'c0000000-0000-4000-8000-000000000083' THEN 'suspended'
    ELSE 'active'
  END
WHERE
  id IN
    (
      'c0000000-0000-4000-8000-000000000081',
      'c0000000-0000-4000-8000-000000000082',
      'c0000000-0000-4000-8000-000000000083'
    );

-- Otto's activities, one of them hidden, and one of Rita's.
INSERT INTO public.activities
  (id, organizer_id, category_id, title, starts_at, location_name, hidden_at)
VALUES
  (
    'f0000000-0000-4000-8000-000000000081',
    'c0000000-0000-4000-8000-000000000082',
    'games',
    'Ticket sale',
    now() + INTERVAL '1 day',
    'Here',
    NULL
  ),
  (
    'f0000000-0000-4000-8000-000000000082',
    'c0000000-0000-4000-8000-000000000082',
    'games',
    'Hidden game',
    now() + INTERVAL '1 day',
    'Here',
    now()
  ),
  (
    'f0000000-0000-4000-8000-000000000083',
    'c0000000-0000-4000-8000-000000000081',
    'games',
    'Rita''s game',
    now() + INTERVAL '1 day',
    'Here',
    NULL
  ),
  (
    'f0000000-0000-4000-8000-000000000084',
    'c0000000-0000-4000-8000-000000000082',
    'games',
    'Another sale',
    now() + INTERVAL '1 day',
    'Here',
    NULL
  ),
  (
    'f0000000-0000-4000-8000-000000000085',
    'c0000000-0000-4000-8000-000000000082',
    'games',
    'One more sale',
    now() + INTERVAL '1 day',
    'Here',
    NULL
  );

SET LOCAL ROLE authenticated;

SELECT set_config(
  'request.jwt.claims',
  '{"sub": "c0000000-0000-4000-8000-000000000081", "email": "rita.reporter@byui.edu"}',
  TRUE
);

-- Reporting
SELECT lives_ok(
  $$select public.report_content(
    'activity', 'f0000000-0000-4000-8000-000000000081', 'spam', '  Selling tickets  '
  )$$,
  'a member reports an activity'
);

SELECT results_eq(
  $$select reporter_id, target_type, target_id, reason, note, status from public.reports$$,
  $$values (
    'c0000000-0000-4000-8000-000000000081'::uuid,
    'activity'::text,
    'f0000000-0000-4000-8000-000000000081'::uuid,
    'spam'::text,
    'Selling tickets'::text,
    'open'::text
  )$$,
  'with a reason and a trimmed note, open, and only their own reports to read'
);

SELECT lives_ok(
  $$select public.report_content('profile', 'c0000000-0000-4000-8000-000000000082', 'unsafe', ' ')$$,
  'a member reports a member, without a note'
);

SELECT results_eq(
  $$select note from public.reports where target_type = 'profile'$$,
  $$values (null::text)$$,
  'a blank note is null'
);

SELECT ok(
  (
    SELECT hidden_at IS NULL
    FROM public.activities
    WHERE id = 'f0000000-0000-4000-8000-000000000081'
  ),
  'a report hides nothing by itself'
);

SELECT throws_ok(
  $$select public.report_content('activity', 'f0000000-0000-4000-8000-000000000081', 'other')$$,
  '23505',
  'ALREADY_REPORTED',
  'a member reports something only once'
);

-- What can't be reported
SELECT throws_ok(
  $$select public.report_content('activity', 'f0000000-0000-4000-8000-000000000082', 'other')$$,
  'P0002',
  'REPORT_TARGET_NOT_FOUND',
  'a hidden activity, which the member can''t see'
);

SELECT throws_ok(
  $$select public.report_content('profile', 'c0000000-0000-4000-8000-000000000083', 'other')$$,
  'P0002',
  'REPORT_TARGET_NOT_FOUND',
  'a member who isn''t active'
);

SELECT throws_ok(
  $$select public.report_content('activity', 'f0000000-0000-4000-8000-0000000000ff', 'other')$$,
  'P0002',
  'REPORT_TARGET_NOT_FOUND',
  'an activity that doesn''t exist'
);

SELECT throws_ok(
  $$select public.report_content('category', 'f0000000-0000-4000-8000-000000000081', 'other')$$,
  'P0002',
  'REPORT_TARGET_NOT_FOUND',
  'anything but an activity or a member'
);

SELECT throws_ok(
  $$select public.report_content('activity', 'f0000000-0000-4000-8000-000000000083', 'other')$$,
  '22023',
  'REPORT_OWN',
  'the member''s own activity'
);

SELECT throws_ok(
  $$select public.report_content('profile', 'c0000000-0000-4000-8000-000000000081', 'other')$$,
  '22023',
  'REPORT_OWN',
  'or their own profile'
);

SELECT throws_ok(
  $$select public.report_content('activity', 'f0000000-0000-4000-8000-000000000084', 'rude')$$,
  '23514',
  NULL,
  'the reason is one of the listed ones'
);

SELECT throws_ok(
  $$select public.report_content(
    'activity', 'f0000000-0000-4000-8000-000000000084', 'other', repeat('a', 501)
  )$$,
  '23514',
  NULL,
  'a note has 500 characters at most'
);

-- 10 in 24 hours. Rita has 2, and 7 more and 1 from yesterday make 9 that count.
RESET ROLE;

INSERT INTO public.reports
  (reporter_id, target_type, target_id, reason, created_at)
SELECT
  'c0000000-0000-4000-8000-000000000081',
  'profile',
  gen_random_uuid(),
  'other',
  CASE
    WHEN n = 8 THEN now() - INTERVAL '25 hours'
    ELSE now()
  END
FROM generate_series(1, 8) AS n;

SET LOCAL ROLE authenticated;

SELECT lives_ok(
  $$select public.report_content('activity', 'f0000000-0000-4000-8000-000000000084', 'spam')$$,
  'the 10th report in 24 hours goes through'
);

SELECT throws_ok(
  $$select public.report_content('activity', 'f0000000-0000-4000-8000-000000000085', 'spam')$$,
  'P0001',
  'REPORT_QUOTA_EXCEEDED',
  'the 11th doesn''t'
);

-- Who reads and writes reports
SELECT throws_ok(
  $$insert into public.reports (reporter_id, target_type, target_id, reason)
  values (auth.uid(), 'activity', 'f0000000-0000-4000-8000-000000000085', 'spam')$$,
  '42501',
  NULL,
  'members can''t add reports directly'
);

SELECT set_config(
  'request.jwt.claims',
  '{"sub": "c0000000-0000-4000-8000-000000000082", "email": "otto.organizer@byui.edu"}',
  TRUE
);

SELECT is_empty('select 1 from public.reports', 'Otto can''t see who reported him');

SELECT set_config(
  'request.jwt.claims',
  '{"sub": "c0000000-0000-4000-8000-000000000083", "email": "sue.suspended@byui.edu"}',
  TRUE
);

SELECT throws_ok(
  $$select public.report_content('activity', 'f0000000-0000-4000-8000-000000000081', 'spam')$$,
  '42501',
  'NOT_ACTIVE',
  'a suspended member can''t report'
);

RESET ROLE;

SELECT ok(
  (SELECT relrowsecurity FROM pg_class WHERE oid = 'public.reports'::regclass),
  'reports have Row Level Security enabled'
);

SELECT table_privs_are(
  'public',
  'reports',
  'authenticated',
  ARRAY['SELECT'],
  'members only read reports, through the policy'
);

SELECT table_privs_are(
  'public',
  'reports',
  'anon',
  ARRAY[]::text[],
  'visitors have no privileges on reports'
);

SELECT *
FROM finish();

ROLLBACK;
