-- Suspending and reinstating a member (MOD-04). Run with `npm run db:test`.
BEGIN;

CREATE EXTENSION IF NOT EXISTS pgtap WITH SCHEMA extensions;

SELECT plan(24);

-- Mo and Mia moderate, Ada is an admin, Otto organizes, and Gwen reported him.
INSERT INTO auth.users
  (id, email, raw_user_meta_data)
VALUES
  (
    'c0000000-0000-4000-8000-0000000000b1',
    'mo.moderator@byui.edu',
    '{"full_name": "Mo Moderator"}'
  ),
  ('c0000000-0000-4000-8000-0000000000b2', 'ada.admin@byui.edu', '{"full_name": "Ada Admin"}'),
  (
    'c0000000-0000-4000-8000-0000000000b3',
    'mia.moderator@byui.edu',
    '{"full_name": "Mia Moderator"}'
  ),
  (
    'c0000000-0000-4000-8000-0000000000b4',
    'otto.organizer@byui.edu',
    '{"full_name": "Otto Organizer"}'
  ),
  ('c0000000-0000-4000-8000-0000000000b5', 'gwen.going@byui.edu', '{"full_name": "Gwen Going"}');

UPDATE public.profiles
SET
  guidelines_version = 1,
  guidelines_accepted_at = now(),
  role = CASE id
    WHEN 'c0000000-0000-4000-8000-0000000000b1' THEN 'moderator'
    WHEN 'c0000000-0000-4000-8000-0000000000b2' THEN 'admin'
    WHEN 'c0000000-0000-4000-8000-0000000000b3' THEN 'moderator'
    ELSE 'member'
  END
WHERE id::text LIKE 'c0000000-0000-4000-8000-0000000000b_';

-- Otto's activities: upcoming, underway, over, cancelled, and already hidden.
INSERT INTO public.activities
  (
    id,
    organizer_id,
    category_id,
    title,
    starts_at,
    location_name,
    status,
    cancelled_at,
    hidden_at,
    hidden_reason
  )
VALUES
  (
    'f0000000-0000-4000-8000-0000000000b1',
    'c0000000-0000-4000-8000-0000000000b4',
    'games',
    'Upcoming',
    now() + INTERVAL '1 day',
    'Here',
    'published',
    NULL,
    NULL,
    NULL
  ),
  (
    'f0000000-0000-4000-8000-0000000000b2',
    'c0000000-0000-4000-8000-0000000000b4',
    'games',
    'Underway',
    now() - INTERVAL '1 hour',
    'Here',
    'published',
    NULL,
    NULL,
    NULL
  ),
  (
    'f0000000-0000-4000-8000-0000000000b3',
    'c0000000-0000-4000-8000-0000000000b4',
    'games',
    'Over',
    now() - INTERVAL '5 hours',
    'Here',
    'published',
    NULL,
    NULL,
    NULL
  ),
  (
    'f0000000-0000-4000-8000-0000000000b4',
    'c0000000-0000-4000-8000-0000000000b4',
    'games',
    'Cancelled',
    now() + INTERVAL '1 day',
    'Here',
    'cancelled',
    now(),
    NULL,
    NULL
  ),
  (
    'f0000000-0000-4000-8000-0000000000b5',
    'c0000000-0000-4000-8000-0000000000b4',
    'games',
    'Hidden',
    now() + INTERVAL '1 day',
    'Here',
    'published',
    NULL,
    now(),
    'Spam'
  );

INSERT INTO public.reports
  (reporter_id, target_type, target_id, reason)
VALUES
  (
    'c0000000-0000-4000-8000-0000000000b5',
    'profile',
    'c0000000-0000-4000-8000-0000000000b4',
    'unsafe'
  ),
  (
    'c0000000-0000-4000-8000-0000000000b5',
    'activity',
    'f0000000-0000-4000-8000-0000000000b1',
    'spam'
  );

SET LOCAL ROLE authenticated;

-- Who can suspend whom
SELECT set_config(
  'request.jwt.claims',
  '{"sub": "c0000000-0000-4000-8000-0000000000b5", "email": "gwen.going@byui.edu"}',
  TRUE
);

SELECT throws_ok(
  $$select public.suspend_member('c0000000-0000-4000-8000-0000000000b4', 'Harassment')$$,
  '42501',
  'NOT_MODERATOR',
  'a member can''t suspend anyone'
);

SELECT set_config(
  'request.jwt.claims',
  '{"sub": "c0000000-0000-4000-8000-0000000000b1", "email": "mo.moderator@byui.edu"}',
  TRUE
);

SELECT throws_ok(
  $$select public.suspend_member('c0000000-0000-4000-8000-0000000000b4', ' ')$$,
  '22023',
  'REASON_REQUIRED',
  'suspending needs a reason'
);

SELECT throws_ok(
  $$select public.suspend_member('c0000000-0000-4000-8000-0000000000ff', 'Harassment')$$,
  'P0002',
  'MEMBER_NOT_FOUND',
  'a member who doesn''t exist can''t be suspended'
);

SELECT throws_ok(
  $$select public.suspend_member('c0000000-0000-4000-8000-0000000000b1', 'Taking a break')$$,
  '22023',
  'SUSPEND_SELF',
  'nor can moderators suspend themselves'
);

SELECT throws_ok(
  $$select public.suspend_member('c0000000-0000-4000-8000-0000000000b3', 'Disagreement')$$,
  '42501',
  'SUSPEND_MODERATOR',
  'or another moderator'
);

-- Suspending
SELECT lives_ok(
  $$select public.suspend_member('c0000000-0000-4000-8000-0000000000b4', '  Harassment  ')$$,
  'a moderator suspends a member'
);

SELECT results_eq(
  $$select status from public.profiles where id = 'c0000000-0000-4000-8000-0000000000b4'$$,
  $$values ('suspended'::text)$$,
  'who is suspended, which moderators can read'
);

SELECT results_eq(
  $$select title, hidden_reason from public.activities
  where organizer_id = 'c0000000-0000-4000-8000-0000000000b4' order by id$$,
  $$values
    ('Upcoming'::text, 'Its organizer was suspended.'::text),
    ('Underway'::text, 'Its organizer was suspended.'::text),
    ('Over'::text, null::text),
    ('Cancelled'::text, null::text),
    ('Hidden'::text, 'Spam'::text)$$,
  'their activities that aren''t over or cancelled are hidden'
);

SELECT results_eq(
  $$select target_type, status, resolution_note from public.reports order by target_type$$,
  $$values
    ('activity'::text, 'actioned'::text, 'Its organizer was suspended.'::text),
    ('profile'::text, 'actioned'::text, 'Harassment'::text)$$,
  'and their open reports, and their activities'', are dealt with'
);

SELECT throws_ok(
  $$select public.suspend_member('c0000000-0000-4000-8000-0000000000b4', 'Again')$$,
  '22023',
  'ALREADY_SUSPENDED',
  'a member is suspended once'
);

-- What a suspended member can do
SELECT set_config(
  'request.jwt.claims',
  '{"sub": "c0000000-0000-4000-8000-0000000000b4", "email": "otto.organizer@byui.edu"}',
  TRUE
);

SELECT results_eq(
  'select id from public.profiles',
  $$values ('c0000000-0000-4000-8000-0000000000b4'::uuid)$$,
  'a suspended member reads only their own profile'
);

SELECT is_empty('select 1 from public.activities', 'and no activities, even their own');

SELECT throws_ok(
  $$select public.create_activity('Comeback', 'games', now() + interval '2 days', 'Here')$$,
  '42501',
  'NOT_ACTIVE',
  'and can''t post'
);

SELECT set_config(
  'request.jwt.claims',
  '{"sub": "c0000000-0000-4000-8000-0000000000b5", "email": "gwen.going@byui.edu"}',
  TRUE
);

SELECT is_empty(
  $$select 1 from public.profiles where id = 'c0000000-0000-4000-8000-0000000000b4'$$,
  'members can''t read a suspended member''s profile'
);

-- Reinstating
SELECT throws_ok(
  $$select public.reinstate_member('c0000000-0000-4000-8000-0000000000b4', 'Apologized')$$,
  '42501',
  'NOT_MODERATOR',
  'a member can''t reinstate anyone'
);

SELECT set_config(
  'request.jwt.claims',
  '{"sub": "c0000000-0000-4000-8000-0000000000b1", "email": "mo.moderator@byui.edu"}',
  TRUE
);

SELECT throws_ok(
  $$select public.reinstate_member('c0000000-0000-4000-8000-0000000000b4', '')$$,
  '22023',
  'REASON_REQUIRED',
  'reinstating needs a reason'
);

SELECT lives_ok(
  $$select public.reinstate_member('c0000000-0000-4000-8000-0000000000b4', ' Apologized ')$$,
  'a moderator reinstates a member'
);

SELECT results_eq(
  $$select status from public.profiles where id = 'c0000000-0000-4000-8000-0000000000b4'$$,
  $$values ('active'::text)$$,
  'who is active again'
);

SELECT results_eq(
  $$select count(*) from public.activities
  where organizer_id = 'c0000000-0000-4000-8000-0000000000b4' and hidden_at is not null$$,
  $$values (3::bigint)$$,
  'and whose activities stay hidden'
);

SELECT throws_ok(
  $$select public.reinstate_member('c0000000-0000-4000-8000-0000000000b4', 'Again')$$,
  '22023',
  'NOT_SUSPENDED',
  'only a suspended member can be reinstated'
);

-- Admins
SELECT set_config(
  'request.jwt.claims',
  '{"sub": "c0000000-0000-4000-8000-0000000000b2", "email": "ada.admin@byui.edu"}',
  TRUE
);

SELECT lives_ok(
  $$select public.suspend_member('c0000000-0000-4000-8000-0000000000b3', 'Shared reports')$$,
  'an admin can suspend a moderator'
);

-- The audit log, which only the owner reads
RESET ROLE;

SELECT ok(
  NOT EXISTS (
    SELECT
    FROM public.profiles
    WHERE id = 'c0000000-0000-4000-8000-0000000000b3' AND status = 'active'
  ),
  'the suspended moderator isn''t active'
);

SELECT results_eq(
  $$select action, target_id, reason, metadata from private.audit_log
  where target_id::text like '%-0000000000b_' order by id$$,
  $$values
    ('hide'::text, 'f0000000-0000-4000-8000-0000000000b2'::uuid, 'Its organizer was suspended.'::text, '{"reports_actioned": 0}'::jsonb),
    ('hide'::text, 'f0000000-0000-4000-8000-0000000000b1'::uuid, 'Its organizer was suspended.'::text, '{"reports_actioned": 1}'::jsonb),
    ('suspend'::text, 'c0000000-0000-4000-8000-0000000000b4'::uuid, 'Harassment'::text, '{"reports_actioned": 1, "activities_hidden": 2}'::jsonb),
    ('reinstate'::text, 'c0000000-0000-4000-8000-0000000000b4'::uuid, 'Apologized'::text, '{}'::jsonb),
    ('suspend'::text, 'c0000000-0000-4000-8000-0000000000b3'::uuid, 'Shared reports'::text, '{"reports_actioned": 0, "activities_hidden": 0}'::jsonb)$$,
  'each hide, suspension and reinstatement writes an audit row'
);

SELECT function_privs_are(
  'public',
  'suspend_member',
  ARRAY['uuid', 'text'],
  'anon',
  ARRAY[]::text[],
  'visitors can''t suspend members'
);

SELECT *
FROM finish();

ROLLBACK;
