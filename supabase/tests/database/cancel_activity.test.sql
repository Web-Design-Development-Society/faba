-- Cancelling and restoring an activity (ACT-05). Run with `npm run db:test`.
BEGIN;

CREATE EXTENSION IF NOT EXISTS pgtap WITH SCHEMA extensions;

SELECT plan(24);

-- Otto organizes, Gwen is going, and Sue is suspended.
INSERT INTO auth.users
  (id, email, raw_user_meta_data)
VALUES
  (
    'c0000000-0000-4000-8000-000000000051',
    'otto.organizer@byui.edu',
    '{"full_name": "Otto Organizer"}'
  ),
  ('c0000000-0000-4000-8000-000000000052', 'gwen.going@byui.edu', '{"full_name": "Gwen Going"}'),
  (
    'c0000000-0000-4000-8000-000000000053',
    'sue.suspended@byui.edu',
    '{"full_name": "Sue Suspended"}'
  );

UPDATE public.profiles
SET
  guidelines_version = 1,
  guidelines_accepted_at = now(),
  status = CASE id
    WHEN 'c0000000-0000-4000-8000-000000000053' THEN 'suspended'
    ELSE 'active'
  END
WHERE
  id IN
    (
      'c0000000-0000-4000-8000-000000000051',
      'c0000000-0000-4000-8000-000000000052',
      'c0000000-0000-4000-8000-000000000053'
    );

-- Upcoming, started an hour ago, and hidden.
INSERT INTO public.activities
  (id, organizer_id, category_id, title, starts_at, location_name, going_count, hidden_at)
VALUES
  (
    'f0000000-0000-4000-8000-000000000051',
    'c0000000-0000-4000-8000-000000000051',
    'outdoors',
    'Sunrise hike',
    now() + INTERVAL '1 day',
    'R Mountain',
    1,
    NULL
  ),
  (
    'f0000000-0000-4000-8000-000000000052',
    'c0000000-0000-4000-8000-000000000051',
    'games',
    'Board game night',
    now() - INTERVAL '1 hour',
    'The library',
    0,
    NULL
  ),
  (
    'f0000000-0000-4000-8000-000000000053',
    'c0000000-0000-4000-8000-000000000051',
    'games',
    'Hidden game',
    now() + INTERVAL '1 day',
    'Here',
    0,
    now()
  );

INSERT INTO public.rsvps
  (activity_id, user_id, status)
VALUES
  ('f0000000-0000-4000-8000-000000000051', 'c0000000-0000-4000-8000-000000000052', 'going');

SET LOCAL ROLE authenticated;

SELECT set_config(
  'request.jwt.claims',
  '{"sub": "c0000000-0000-4000-8000-000000000051", "email": "otto.organizer@byui.edu"}',
  TRUE
);

-- Cancelling
SELECT lives_ok(
  $$select public.cancel_activity('f0000000-0000-4000-8000-000000000051', ' Rained out ')$$,
  'the organizer cancels their activity'
);

SELECT results_eq(
  $$select status, cancel_reason, cancelled_at = now(), going_count
  from public.activities where id = 'f0000000-0000-4000-8000-000000000051'$$,
  $$values ('cancelled'::text, 'Rained out'::text, true, 1)$$,
  'it''s marked cancelled, with the trimmed reason, and keeps its count'
);

SELECT results_eq(
  $$select status from public.rsvps
  where activity_id = 'f0000000-0000-4000-8000-000000000051'
    and user_id = 'c0000000-0000-4000-8000-000000000052'$$,
  $$values ('going'::text)$$,
  'attendees stay going, so they still find it'
);

SELECT lives_ok(
  $$select public.cancel_activity('f0000000-0000-4000-8000-000000000051', 'Snowed in')$$,
  'cancelling it again works'
);

SELECT extensions.is(
  (SELECT cancel_reason FROM public.activities WHERE id = 'f0000000-0000-4000-8000-000000000051'),
  'Rained out',
  'and changes nothing'
);

SELECT throws_ok(
  $$select public.cancel_activity('f0000000-0000-4000-8000-000000000053', repeat('a', 201))$$,
  '23514',
  NULL,
  'the reason is 200 characters at most'
);

SELECT lives_ok(
  $$select public.cancel_activity('f0000000-0000-4000-8000-000000000053', ' ')$$,
  'the organizer cancels a hidden activity'
);

SELECT extensions.is(
  (SELECT cancel_reason FROM public.activities WHERE id = 'f0000000-0000-4000-8000-000000000053'),
  NULL,
  'a blank reason is stored as NULL'
);

SELECT lives_ok(
  $$select public.cancel_activity('f0000000-0000-4000-8000-000000000052')$$,
  'the organizer cancels an activity that has started, without a reason'
);

-- Restoring
SELECT lives_ok(
  $$select public.restore_activity('f0000000-0000-4000-8000-000000000051')$$,
  'the organizer restores their activity before it starts'
);

SELECT results_eq(
  $$select status, cancel_reason, cancelled_at
  from public.activities where id = 'f0000000-0000-4000-8000-000000000051'$$,
  $$values ('published'::text, null::text, null::timestamptz)$$,
  'it''s back on, without the reason'
);

SELECT lives_ok(
  $$select public.restore_activity('f0000000-0000-4000-8000-000000000051')$$,
  'restoring one that isn''t cancelled changes nothing'
);

SELECT throws_ok(
  $$select public.restore_activity('f0000000-0000-4000-8000-000000000052')$$,
  '22023',
  'RESTORE_TOO_LATE',
  'an activity that has started stays cancelled'
);

SELECT throws_ok(
  $$delete from public.activities where id = 'f0000000-0000-4000-8000-000000000051'$$,
  '42501',
  NULL,
  'the organizer can''t delete it'
);

-- Who can't
SELECT set_config(
  'request.jwt.claims',
  '{"sub": "c0000000-0000-4000-8000-000000000052", "email": "gwen.going@byui.edu"}',
  TRUE
);

SELECT throws_ok(
  $$select public.cancel_activity('f0000000-0000-4000-8000-000000000051')$$,
  '42501',
  'NOT_ORGANIZER',
  'another member can''t cancel it'
);

SELECT throws_ok(
  $$select public.restore_activity('f0000000-0000-4000-8000-000000000053')$$,
  '42501',
  'NOT_ORGANIZER',
  'or restore it'
);

SELECT throws_ok(
  $$select public.cancel_activity('f0000000-0000-4000-8000-000000000059')$$,
  '42501',
  'NOT_ORGANIZER',
  'an activity that doesn''t exist fails the same way'
);

SELECT throws_ok(
  $$update public.activities set status = 'cancelled', cancelled_at = now()
  where id = 'f0000000-0000-4000-8000-000000000051'$$,
  '42501',
  NULL,
  'members can''t cancel directly'
);

SELECT set_config(
  'request.jwt.claims',
  '{"sub": "c0000000-0000-4000-8000-000000000053", "email": "sue.suspended@byui.edu"}',
  TRUE
);

SELECT throws_ok(
  $$select public.cancel_activity('f0000000-0000-4000-8000-000000000051')$$,
  '42501',
  'NOT_ACTIVE',
  'a suspended member can''t cancel'
);

SELECT throws_ok(
  $$select public.restore_activity('f0000000-0000-4000-8000-000000000053')$$,
  '42501',
  'NOT_ACTIVE',
  'or restore'
);

RESET role;

SELECT ok(
  NOT has_function_privilege('anon', 'public.cancel_activity(uuid, text)', 'execute'),
  'signed-out visitors can''t cancel'
);

SELECT ok(
  NOT has_function_privilege('anon', 'public.restore_activity(uuid)', 'execute'),
  'or restore'
);

SELECT ok(
  has_function_privilege('authenticated', 'public.cancel_activity(uuid, text)', 'execute'),
  'signed-in users can call cancel_activity'
);

SELECT ok(
  has_function_privilege('authenticated', 'public.restore_activity(uuid)', 'execute'),
  'and restore_activity'
);

SELECT *
FROM finish();

ROLLBACK;
