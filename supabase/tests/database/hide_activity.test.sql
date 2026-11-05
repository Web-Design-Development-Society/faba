-- Hiding and unhiding an activity (MOD-03). Run with `npm run db:test`.
BEGIN;

CREATE EXTENSION IF NOT EXISTS pgtap WITH SCHEMA extensions;

SELECT plan(21);

-- Mo moderates, Otto organizes, and Gwen and Rita are members.
INSERT INTO auth.users
  (id, email, raw_user_meta_data)
VALUES
  (
    'c0000000-0000-4000-8000-0000000000a1',
    'mo.moderator@byui.edu',
    '{"full_name": "Mo Moderator"}'
  ),
  (
    'c0000000-0000-4000-8000-0000000000a2',
    'otto.organizer@byui.edu',
    '{"full_name": "Otto Organizer"}'
  ),
  ('c0000000-0000-4000-8000-0000000000a3', 'gwen.going@byui.edu', '{"full_name": "Gwen Going"}'),
  (
    'c0000000-0000-4000-8000-0000000000a4',
    'rita.reporter@byui.edu',
    '{"full_name": "Rita Reporter"}'
  );

UPDATE public.profiles
SET
  guidelines_version = 1,
  guidelines_accepted_at = now(),
  role = CASE id
    WHEN 'c0000000-0000-4000-8000-0000000000a1' THEN 'moderator'
    ELSE 'member'
  END
WHERE id::text LIKE 'c0000000-0000-4000-8000-0000000000a_';

INSERT INTO public.activities
  (id, organizer_id, category_id, title, starts_at, location_name)
VALUES
  (
    'f0000000-0000-4000-8000-0000000000a1',
    'c0000000-0000-4000-8000-0000000000a2',
    'games',
    'Ticket sale',
    now() + INTERVAL '1 day',
    'Here'
  ),
  (
    'f0000000-0000-4000-8000-0000000000a2',
    'c0000000-0000-4000-8000-0000000000a2',
    'games',
    'Board game night',
    now() + INTERVAL '1 day',
    'Here'
  );

-- Gwen and Rita reported the sale, and Gwen the game night.
INSERT INTO public.reports
  (reporter_id, target_type, target_id, reason)
VALUES
  (
    'c0000000-0000-4000-8000-0000000000a3',
    'activity',
    'f0000000-0000-4000-8000-0000000000a1',
    'spam'
  ),
  (
    'c0000000-0000-4000-8000-0000000000a4',
    'activity',
    'f0000000-0000-4000-8000-0000000000a1',
    'spam'
  ),
  (
    'c0000000-0000-4000-8000-0000000000a3',
    'activity',
    'f0000000-0000-4000-8000-0000000000a2',
    'other'
  );

SET LOCAL ROLE authenticated;

-- Hiding
SELECT set_config(
  'request.jwt.claims',
  '{"sub": "c0000000-0000-4000-8000-0000000000a3", "email": "gwen.going@byui.edu"}',
  TRUE
);

SELECT throws_ok(
  $$select public.moderate_hide('f0000000-0000-4000-8000-0000000000a1', 'Spam')$$,
  '42501',
  'NOT_MODERATOR',
  'a member can''t hide an activity'
);

SELECT set_config(
  'request.jwt.claims',
  '{"sub": "c0000000-0000-4000-8000-0000000000a1", "email": "mo.moderator@byui.edu"}',
  TRUE
);

SELECT throws_ok(
  $$select public.moderate_hide('f0000000-0000-4000-8000-0000000000a1', ' ')$$,
  '22023',
  'REASON_REQUIRED',
  'hiding needs a reason'
);

SELECT throws_ok(
  $$select public.moderate_hide('f0000000-0000-4000-8000-0000000000a1', repeat('a', 501))$$,
  '23514',
  NULL,
  'of 500 characters at most'
);

SELECT throws_ok(
  $$select public.moderate_hide('f0000000-0000-4000-8000-0000000000ff', 'Spam')$$,
  'P0002',
  'ACTIVITY_NOT_FOUND',
  'an activity that doesn''t exist can''t be hidden'
);

SELECT lives_ok(
  $$select public.moderate_hide('f0000000-0000-4000-8000-0000000000a1', '  Selling tickets  ')$$,
  'a moderator hides an activity'
);

SELECT results_eq(
  $$select hidden_reason, hidden_by, hidden_at = now()
  from public.activities where id = 'f0000000-0000-4000-8000-0000000000a1'$$,
  $$values ('Selling tickets'::text, 'c0000000-0000-4000-8000-0000000000a1'::uuid, true)$$,
  'with the reason, who hid it and when'
);

SELECT results_eq(
  $$select target_id, status, resolved_by, resolution_note from public.reports order by status, target_id$$,
  $$values
    ('f0000000-0000-4000-8000-0000000000a1'::uuid, 'actioned'::text, 'c0000000-0000-4000-8000-0000000000a1'::uuid, 'Selling tickets'::text),
    ('f0000000-0000-4000-8000-0000000000a1'::uuid, 'actioned'::text, 'c0000000-0000-4000-8000-0000000000a1'::uuid, 'Selling tickets'::text),
    ('f0000000-0000-4000-8000-0000000000a2'::uuid, 'open'::text, null::uuid, null::text)$$,
  'its open reports are dealt with, and other activities'' stay open'
);

SELECT throws_ok(
  $$select public.moderate_hide('f0000000-0000-4000-8000-0000000000a1', 'Again')$$,
  '22023',
  'ALREADY_HIDDEN',
  'an activity is hidden once'
);

SELECT results_eq(
  $$select id from public.activities where id = 'f0000000-0000-4000-8000-0000000000a1'$$,
  $$values ('f0000000-0000-4000-8000-0000000000a1'::uuid)$$,
  'moderators still read a hidden activity'
);

-- Who sees a hidden activity
SELECT set_config(
  'request.jwt.claims',
  '{"sub": "c0000000-0000-4000-8000-0000000000a3", "email": "gwen.going@byui.edu"}',
  TRUE
);

SELECT is_empty(
  $$select 1 from public.activities where id = 'f0000000-0000-4000-8000-0000000000a1'$$,
  'members don''t'
);

SELECT set_config(
  'request.jwt.claims',
  '{"sub": "c0000000-0000-4000-8000-0000000000a2", "email": "otto.organizer@byui.edu"}',
  TRUE
);

SELECT results_eq(
  $$select hidden_reason from public.activities where id = 'f0000000-0000-4000-8000-0000000000a1'$$,
  $$values ('Selling tickets'::text)$$,
  'its organizer does, with the reason'
);

-- Unhiding
SELECT throws_ok(
  $$select public.moderate_unhide('f0000000-0000-4000-8000-0000000000a1', 'Fixed it')$$,
  '42501',
  'NOT_MODERATOR',
  'the organizer can''t unhide it'
);

SELECT set_config(
  'request.jwt.claims',
  '{"sub": "c0000000-0000-4000-8000-0000000000a1", "email": "mo.moderator@byui.edu"}',
  TRUE
);

SELECT throws_ok(
  $$select public.moderate_unhide('f0000000-0000-4000-8000-0000000000a1', '')$$,
  '22023',
  'REASON_REQUIRED',
  'unhiding needs a reason'
);

SELECT lives_ok(
  $$select public.moderate_unhide('f0000000-0000-4000-8000-0000000000a1', ' The sale is gone ')$$,
  'a moderator unhides it'
);

SELECT results_eq(
  $$select hidden_at, hidden_reason, hidden_by
  from public.activities where id = 'f0000000-0000-4000-8000-0000000000a1'$$,
  $$values (null::timestamptz, null::text, null::uuid)$$,
  'which clears the reason and who hid it'
);

SELECT throws_ok(
  $$select public.moderate_unhide('f0000000-0000-4000-8000-0000000000a1', 'Again')$$,
  '22023',
  'NOT_HIDDEN',
  'only a hidden activity can be unhidden'
);

SELECT set_config(
  'request.jwt.claims',
  '{"sub": "c0000000-0000-4000-8000-0000000000a3", "email": "gwen.going@byui.edu"}',
  TRUE
);

SELECT results_eq(
  $$select id from public.activities where id = 'f0000000-0000-4000-8000-0000000000a1'$$,
  $$values ('f0000000-0000-4000-8000-0000000000a1'::uuid)$$,
  'members see it again'
);

-- The audit log, which only the owner reads
RESET ROLE;

SELECT results_eq(
  $$select actor_id, action, target_type, target_id, reason, metadata
  from private.audit_log where target_id = 'f0000000-0000-4000-8000-0000000000a1' order by id$$,
  $$values
    (
      'c0000000-0000-4000-8000-0000000000a1'::uuid,
      'hide'::text,
      'activity'::text,
      'f0000000-0000-4000-8000-0000000000a1'::uuid,
      'Selling tickets'::text,
      '{"reports_actioned": 2}'::jsonb
    ),
    (
      'c0000000-0000-4000-8000-0000000000a1'::uuid,
      'unhide'::text,
      'activity'::text,
      'f0000000-0000-4000-8000-0000000000a1'::uuid,
      'The sale is gone'::text,
      '{"hidden_reason": "Selling tickets"}'::jsonb
    )$$,
  'hiding and unhiding each write an audit row'
);

SELECT throws_ok(
  $$update public.activities set hidden_reason = repeat('a', 501)
  where id = 'f0000000-0000-4000-8000-0000000000a2'$$,
  '23514',
  NULL,
  'a hidden reason has 500 characters at most'
);

SELECT function_privs_are(
  'public',
  'moderate_hide',
  ARRAY['uuid', 'text'],
  'anon',
  ARRAY[]::text[],
  'visitors can''t hide activities'
);

SELECT function_privs_are(
  'public',
  'moderate_unhide',
  ARRAY['uuid', 'text'],
  'anon',
  ARRAY[]::text[],
  'or unhide them'
);

SELECT *
FROM finish();

ROLLBACK;
