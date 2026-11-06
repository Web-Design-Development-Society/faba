-- Handing over an ineligible organizer's activities (AUTH-05). Run with `npm run db:test`.
BEGIN;

CREATE EXTENSION IF NOT EXISTS pgtap WITH SCHEMA extensions;

SELECT plan(15);

-- Mo moderates. Ivy left BYU-Idaho, and Otto still organizes. Gus is going to Ivy's hike, and
-- Nell isn't.
INSERT INTO auth.users
  (id, email, raw_user_meta_data)
SELECT
  ('c0000000-0000-4000-8000-0000000001b' || n)::uuid,
  name || '@byui.edu',
  jsonb_build_object('full_name', name)
FROM (
  VALUES
    (1, 'mo'),
    (2, 'ivy'),
    (3, 'otto'),
    (4, 'gus'),
    (5, 'nell')
) AS v (n, name);

UPDATE public.profiles
SET
  guidelines_version = 1,
  guidelines_accepted_at = now(),
  role = CASE id
    WHEN 'c0000000-0000-4000-8000-0000000001b1' THEN 'moderator'
    ELSE 'member'
  END,
  status = CASE id
    WHEN 'c0000000-0000-4000-8000-0000000001b2' THEN 'ineligible'
    ELSE 'active'
  END
WHERE id::text LIKE 'c0000000-0000-4000-8000-0000000001b_';

INSERT INTO public.activities
  (id, organizer_id, category_id, title, starts_at, location_name, going_count)
VALUES
  (
    'f0000000-0000-4000-8000-0000000001b1',
    'c0000000-0000-4000-8000-0000000001b2',
    'outdoors',
    'Ivy''s hike',
    now() + INTERVAL '1 day',
    'R Mountain',
    2
  ),
  (
    'f0000000-0000-4000-8000-0000000001b2',
    'c0000000-0000-4000-8000-0000000001b2',
    'games',
    'Ivy''s game night',
    now() + INTERVAL '2 days',
    'Here',
    1
  ),
  (
    'f0000000-0000-4000-8000-0000000001b3',
    'c0000000-0000-4000-8000-0000000001b2',
    'games',
    'Ivy''s lunch',
    now() - INTERVAL '1 hour',
    'Here',
    1
  ),
  (
    'f0000000-0000-4000-8000-0000000001b4',
    'c0000000-0000-4000-8000-0000000001b3',
    'games',
    'Otto''s game night',
    now() + INTERVAL '1 day',
    'Here',
    1
  );

INSERT INTO public.rsvps
  (activity_id, user_id, status)
VALUES
  ('f0000000-0000-4000-8000-0000000001b1', 'c0000000-0000-4000-8000-0000000001b2', 'going'),
  ('f0000000-0000-4000-8000-0000000001b1', 'c0000000-0000-4000-8000-0000000001b4', 'going'),
  ('f0000000-0000-4000-8000-0000000001b2', 'c0000000-0000-4000-8000-0000000001b2', 'going'),
  ('f0000000-0000-4000-8000-0000000001b3', 'c0000000-0000-4000-8000-0000000001b2', 'going'),
  ('f0000000-0000-4000-8000-0000000001b4', 'c0000000-0000-4000-8000-0000000001b3', 'going');

SET LOCAL ROLE authenticated;

-- Who can, and when
SELECT set_config(
  'request.jwt.claims',
  '{"sub": "c0000000-0000-4000-8000-0000000001b4", "email": "gus@byui.edu"}',
  TRUE
);

SELECT throws_ok(
  $$select public.moderate_transfer_activity('f0000000-0000-4000-8000-0000000001b1',
  'c0000000-0000-4000-8000-0000000001b4', 'I''ll host')$$,
  '42501',
  'NOT_MODERATOR',
  'members can''t hand over an activity'
);

SELECT set_config(
  'request.jwt.claims',
  '{"sub": "c0000000-0000-4000-8000-0000000001b1", "email": "mo@byui.edu"}',
  TRUE
);

SELECT throws_ok(
  $$select public.moderate_cancel_activity('f0000000-0000-4000-8000-0000000001b2', ' ')$$,
  '22023',
  'REASON_REQUIRED',
  'moderators give a reason'
);

SELECT throws_ok(
  $$select public.moderate_cancel_activity('f0000000-0000-4000-8000-0000000001b4', 'Gone')$$,
  '22023',
  'ORGANIZER_ELIGIBLE',
  'and only for an organizer who''s no longer eligible'
);

SELECT throws_ok(
  $$select public.moderate_cancel_activity('f0000000-0000-4000-8000-0000000001b3', 'Gone')$$,
  '22023',
  'ACTIVITY_NOT_UPCOMING',
  'and only before it starts'
);

SELECT throws_ok(
  $$select public.moderate_transfer_activity('f0000000-0000-4000-8000-0000000001b1',
  'c0000000-0000-4000-8000-0000000001b5', 'Nell will host')$$,
  '22023',
  'NEW_HOST_NOT_GOING',
  'the new host must be going'
);

-- Transferring
SELECT lives_ok(
  $$select public.moderate_transfer_activity('f0000000-0000-4000-8000-0000000001b1',
  'c0000000-0000-4000-8000-0000000001b4', 'Gus agreed to host')$$,
  'a moderator gives the hike to Gus'
);

SELECT results_eq(
  $$select organizer_id, going_count from public.activities
  where id = 'f0000000-0000-4000-8000-0000000001b1'$$,
  $$values ('c0000000-0000-4000-8000-0000000001b4'::uuid, 2)$$,
  'who now organizes it, with the same count'
);

SELECT set_config(
  'request.jwt.claims',
  '{"sub": "c0000000-0000-4000-8000-0000000001b4", "email": "gus@byui.edu"}',
  TRUE
);

SELECT throws_ok(
  $$select public.rsvp('f0000000-0000-4000-8000-0000000001b1', 'not_going')$$,
  '22023',
  'ORGANIZER_GOING',
  'and stays going, like any organizer'
);

-- Cancelling
SELECT set_config(
  'request.jwt.claims',
  '{"sub": "c0000000-0000-4000-8000-0000000001b1", "email": "mo@byui.edu"}',
  TRUE
);

SELECT lives_ok(
  $$select public.moderate_cancel_activity('f0000000-0000-4000-8000-0000000001b2',
  'Nobody can host')$$,
  'a moderator cancels the game night'
);

SELECT results_eq(
  $$select status, cancel_reason from public.activities
  where id = 'f0000000-0000-4000-8000-0000000001b2'$$,
  $$values ('cancelled'::text, 'Its organizer is no longer active.'::text)$$,
  'which says why'
);

SELECT throws_ok(
  $$select public.moderate_transfer_activity('f0000000-0000-4000-8000-0000000001b2',
  'c0000000-0000-4000-8000-0000000001b4', 'Gus agreed')$$,
  '22023',
  'ACTIVITY_NOT_UPCOMING',
  'and then can''t change hands'
);

RESET ROLE;

SELECT results_eq(
  $$select actor_id, action, target_id, reason, metadata from private.audit_log
  where target_id::text like 'f0000000-0000-4000-8000-0000000001b_' order by id$$,
  $$values
    (
      'c0000000-0000-4000-8000-0000000001b1'::uuid,
      'transfer_activity'::text,
      'f0000000-0000-4000-8000-0000000001b1'::uuid,
      'Gus agreed to host'::text,
      jsonb_build_object(
        'from', 'c0000000-0000-4000-8000-0000000001b2',
        'to', 'c0000000-0000-4000-8000-0000000001b4'
      )
    ),
    (
      'c0000000-0000-4000-8000-0000000001b1'::uuid,
      'cancel_activity'::text,
      'f0000000-0000-4000-8000-0000000001b2'::uuid,
      'Nobody can host'::text,
      '{"going_count": 1}'::jsonb
    )$$,
  'each writes to the audit log, and nothing else does'
);

SELECT function_privs_are(
  'public',
  'moderate_transfer_activity',
  ARRAY['uuid', 'uuid', 'text'],
  'anon',
  ARRAY[]::text[],
  'visitors can''t transfer activities'
);

SELECT function_privs_are(
  'public',
  'moderate_cancel_activity',
  ARRAY['uuid', 'text'],
  'anon',
  ARRAY[]::text[],
  'or cancel them'
);

SELECT function_privs_are(
  'private',
  'lock_handover',
  ARRAY['uuid', 'text'],
  'authenticated',
  ARRAY[]::text[],
  'and members can''t call the check directly'
);

SELECT *
FROM finish();

ROLLBACK;
