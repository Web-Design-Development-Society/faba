-- Who can read what (design document section 9.8). Signed-out visitors read nothing. Active
-- byui.edu members read categories, activities that aren't hidden, and active profiles. Everyone
-- else signed in reads only their own profile. Run with `npm run db:test`.
BEGIN;

CREATE EXTENSION IF NOT EXISTS pgtap WITH SCHEMA extensions;

SELECT plan(17);

-- Expected counts, worked out before switching roles. Every role can read these settings.
SELECT set_config('test.categories', (SELECT count(*)::text FROM public.categories), TRUE);

SELECT set_config(
  'test.visible_activities',
  (SELECT count(*)::text FROM public.activities WHERE hidden_at IS NULL),
  TRUE
);

SELECT set_config(
  'test.active_profiles',
  (SELECT count(*)::text FROM public.profiles WHERE status = 'active'),
  TRUE
);

-- A hidden activity by the organizer persona, who is active.
INSERT INTO public.activities
  (organizer_id, category_id, title, starts_at, location_name, hidden_at, hidden_reason)
VALUES
  (
    '00000000-0000-4000-8000-000000000002',
    'games',
    'Hidden board game night',
    now() + INTERVAL '3 days',
    'Rexburg',
    now(),
    'Hidden for the test'
  );

-- Signed-out visitors
SET LOCAL ROLE anon;

SELECT throws_ok(
  'select 1 from public.categories',
  '42501',
  NULL,
  'signed-out visitors can''t read categories'
);

SELECT throws_ok(
  'select 1 from public.activities',
  '42501',
  NULL,
  'signed-out visitors can''t read activities'
);

SELECT throws_ok(
  'select 1 from public.profiles',
  '42501',
  NULL,
  'signed-out visitors can''t read profiles'
);

-- An active member
SET LOCAL ROLE authenticated;

SELECT set_config(
  'request.jwt.claims',
  '{"sub": "00000000-0000-4000-8000-000000000001", "email": "member.test@byui.edu"}',
  TRUE
);

SELECT ok(private.is_active_member(), 'an active byui.edu member is an active member');

SELECT extensions.is(
  (SELECT count(*)::text FROM public.categories),
  current_setting('test.categories'),
  'an active member reads every category'
);

SELECT extensions.is(
  (SELECT count(*)::text FROM public.activities),
  current_setting('test.visible_activities'),
  'an active member reads every activity that isn''t hidden'
);

SELECT is_empty(
  'select 1 from public.activities where hidden_at is not null',
  'an active member reads no hidden activities'
);

SELECT extensions.is(
  (SELECT count(*)::text FROM public.profiles),
  current_setting('test.active_profiles'),
  'an active member reads every active profile'
);

SELECT is_empty(
  'select 1 from public.profile_private',
  'an active member reads no private profile data yet'
);

SELECT throws_ok(
  'delete from public.activities',
  '42501',
  NULL,
  'an active member can''t write to tables directly'
);

-- The organizer of the hidden activity
SELECT set_config(
  'request.jwt.claims',
  '{"sub": "00000000-0000-4000-8000-000000000002", "email": "organizer.test@byui.edu"}',
  TRUE
);

SELECT extensions.is(
  (SELECT title FROM public.activities WHERE hidden_at IS NOT NULL),
  'Hidden board game night',
  'an organizer reads their own hidden activity, and no one else''s'
);

-- A suspended member
SELECT set_config(
  'request.jwt.claims',
  '{"sub": "00000000-0000-4000-8000-000000000005", "email": "suspended.test@byui.edu"}',
  TRUE
);

SELECT is_empty('select 1 from public.categories', 'a suspended member reads no categories');

SELECT is_empty(
  'select 1 from public.activities',
  'a suspended member reads no activities, not even their own'
);

SELECT results_eq(
  'select id from public.profiles',
  $$values ('00000000-0000-4000-8000-000000000005'::uuid)$$,
  'a suspended member reads only their own profile'
);

-- A session whose email isn't byui.edu, for the active member's account
SELECT set_config(
  'request.jwt.claims',
  '{"sub": "00000000-0000-4000-8000-000000000001", "email": "member.test@gmail.com"}',
  TRUE
);

SELECT ok(
  NOT private.is_active_member(),
  'a session with an email that isn''t byui.edu isn''t an active member'
);

SELECT is_empty(
  'select 1 from public.activities',
  'a session with an email that isn''t byui.edu reads no activities'
);

SELECT results_eq(
  'select id from public.profiles',
  $$values ('00000000-0000-4000-8000-000000000001'::uuid)$$,
  'a session with an email that isn''t byui.edu reads only its own profile'
);

RESET role;

SELECT *
FROM finish();

ROLLBACK;
