-- Channel preferences, quiet hours and reminder timing (NOTIF-13). Run with `npm run db:test`.
BEGIN;

CREATE EXTENSION IF NOT EXISTS pgtap WITH SCHEMA extensions;

SELECT plan(7);

INSERT INTO auth.users
  (id, email, raw_user_meta_data)
VALUES
  ('c0000000-0000-4000-8000-000000001901', 'ivy@byui.edu', '{"full_name": "Ivy Quiet"}');

UPDATE public.profiles
SET
  guidelines_version = 1,
  guidelines_accepted_at = now()
WHERE id = 'c0000000-0000-4000-8000-000000001901';

-- Quiet hours default to 9 PM to 7 AM. 11 PM Boise time is quiet, and noon isn't.
SELECT ok(
  private.in_quiet_hours(
    'c0000000-0000-4000-8000-000000001901',
    '2026-11-12 05:00:00+00'::timestamptz
  ),
  'at 10 PM Boise time, the default quiet hours apply'
);

SELECT ok(
  NOT private.in_quiet_hours(
    'c0000000-0000-4000-8000-000000001901',
    '2026-11-12 18:00:00+00'::timestamptz
  ),
  'at noon, the default quiet hours don''t apply'
);

SET LOCAL ROLE authenticated;

SELECT set_config(
  'request.jwt.claims',
  '{"sub": "c0000000-0000-4000-8000-000000001901", "email": "ivy@byui.edu"}',
  TRUE
);

SELECT lives_ok(
  $$select public.set_channel_settings(time '22:30', time '06:30', 6)$$,
  'a member sets quiet hours and a reminder lead time'
);

SELECT throws_ok(
  $$select public.set_channel_settings(time '22:30', time '06:30', 5)$$,
  '22023',
  'INVALID_LEAD_TIME',
  'a reminder lead time is 1, 2, 6 or 24 hours'
);

SELECT lives_ok(
  $$select public.set_channel_choice('reminder', 'email', false)$$,
  'a member turns off email reminders'
);

SELECT throws_ok(
  $$select public.set_channel_choice('reminder', 'sms', false)$$,
  '23514',
  NULL,
  'only in-app and email are channels'
);

SELECT results_eq(
  $$select enabled from public.notification_channel_choices where type = 'reminder' and channel = 'email'$$,
  $$values (false)$$,
  'the choice is saved'
);

ROLLBACK;
