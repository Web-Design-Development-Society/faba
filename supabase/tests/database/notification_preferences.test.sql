-- Notification preferences (NOTIF-10). Run with `npm run db:test`.
BEGIN;

CREATE EXTENSION IF NOT EXISTS pgtap WITH SCHEMA extensions;

SELECT plan(8);

-- Max is a member. Tia can't see Max's choices.
INSERT INTO auth.users
  (id, email, raw_user_meta_data)
VALUES
  ('c0000000-0000-4000-8000-000000000601', 'tia@byui.edu', '{"full_name": "Tia Member"}'),
  ('c0000000-0000-4000-8000-000000000602', 'max@byui.edu', '{"full_name": "Max Member"}');

UPDATE public.profiles
SET
  guidelines_version = 1,
  guidelines_accepted_at = now()
WHERE id BETWEEN 'c0000000-0000-4000-8000-000000000601' AND 'c0000000-0000-4000-8000-000000000602';

-- Nothing is turned off by default, so Max is told.
SELECT results_eq(
  $$select private.notify(array['c0000000-0000-4000-8000-000000000602']::uuid[], 'new_attendees', null, '{}'::jsonb, 'default-on')$$,
  $$values (1)$$,
  'a type is on by default'
);

-- Max turns off new attendees, through the function.
SET LOCAL ROLE authenticated;

SELECT set_config(
  'request.jwt.claims',
  '{"sub": "c0000000-0000-4000-8000-000000000602", "email": "max@byui.edu"}',
  TRUE
);

SELECT lives_ok(
  $$select public.set_notification_preferences(array['new_attendees'])$$,
  'a member can turn a type off'
);

RESET ROLE;

SELECT results_eq(
  $$select private.notify(array['c0000000-0000-4000-8000-000000000602']::uuid[], 'new_attendees', null, '{}'::jsonb, 'turned-off')$$,
  $$values (0)$$,
  'a type that is turned off makes no notification'
);

-- Max also tries to turn off cancellations. They stay on.
SELECT results_eq(
  $$select private.notify(array['c0000000-0000-4000-8000-000000000602']::uuid[], 'activity_cancelled', null, '{}'::jsonb, 'cancel-stays-on')$$,
  $$values (1)$$,
  'cancellations come even when a member has turned them off'
);

-- Tia can't read Max's choices.
SET LOCAL ROLE authenticated;

SELECT set_config(
  'request.jwt.claims',
  '{"sub": "c0000000-0000-4000-8000-000000000601", "email": "tia@byui.edu"}',
  TRUE
);

SELECT results_eq(
  $$select count(*)::int from public.notification_preferences where user_id = 'c0000000-0000-4000-8000-000000000602'$$,
  $$values (0)$$,
  'another member can''t see someone else''s choices'
);

-- Writes don't go through the table, only the function.
SELECT throws_ok(
  $$insert into public.notification_preferences (user_id, type) values ('c0000000-0000-4000-8000-000000000601', 'reminder')$$,
  '42501',
  NULL,
  'a member can''t write preferences straight to the table'
);

-- Max turns everything back on, and the notification comes again.
SELECT set_config(
  'request.jwt.claims',
  '{"sub": "c0000000-0000-4000-8000-000000000602", "email": "max@byui.edu"}',
  TRUE
);

SELECT lives_ok(
  $$select public.set_notification_preferences(array[]::text[])$$,
  'a member can turn a type back on'
);

RESET ROLE;

SELECT results_eq(
  $$select private.notify(array['c0000000-0000-4000-8000-000000000602']::uuid[], 'new_attendees', null, '{}'::jsonb, 'turned-back-on')$$,
  $$values (1)$$,
  'a type turned back on is notified again'
);

SELECT * FROM finish();
ROLLBACK;
