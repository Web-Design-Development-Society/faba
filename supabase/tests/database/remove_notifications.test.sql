-- Remove alerts (NOTIF-21). Run with `npm run db:test`.
BEGIN;

CREATE EXTENSION IF NOT EXISTS pgtap WITH SCHEMA extensions;

SELECT plan(15);

-- Ola organizes a hike in an hour, and Rae and Ron are going.
INSERT INTO auth.users
  (id, email, raw_user_meta_data)
SELECT
  ('c0000000-0000-4000-8000-00000000051' || n)::uuid,
  name || '@byui.edu',
  jsonb_build_object('full_name', name)
FROM (
  VALUES
    (1, 'ola'),
    (2, 'rae'),
    (3, 'ron')
) AS v (n, name);

UPDATE public.profiles
SET
  guidelines_version = 1,
  guidelines_accepted_at = now()
WHERE id::text LIKE 'c0000000-0000-4000-8000-00000000051_';

INSERT INTO public.activities
  (id, organizer_id, category_id, title, starts_at, location_name)
VALUES
  (
    'f0000000-0000-4000-8000-000000000511',
    'c0000000-0000-4000-8000-000000000511',
    'outdoors',
    'Sunrise hike',
    now() + INTERVAL '1 hour',
    'R Mountain'
  );

INSERT INTO public.rsvps
  (activity_id, user_id, status, updated_at)
VALUES
  (
    'f0000000-0000-4000-8000-000000000511',
    'c0000000-0000-4000-8000-000000000512',
    'going',
    now() - INTERVAL '1 day'
  ),
  (
    'f0000000-0000-4000-8000-000000000511',
    'c0000000-0000-4000-8000-000000000513',
    'going',
    now() - INTERVAL '1 day'
  );

-- Rae has a change and a reminder, both new, and a confirmation she's read. Ron has a change.
INSERT INTO public.notifications
  (id, recipient_id, type, activity_id, dedupe_key, read_at)
VALUES
  (
    'e0000000-0000-4000-8000-000000000511',
    'c0000000-0000-4000-8000-000000000512',
    'activity_changed',
    'f0000000-0000-4000-8000-000000000511',
    'changed:hike',
    NULL
  ),
  (
    'e0000000-0000-4000-8000-000000000512',
    'c0000000-0000-4000-8000-000000000512',
    'reminder',
    'f0000000-0000-4000-8000-000000000511',
    'reminder:f0000000-0000-4000-8000-000000000511',
    NULL
  ),
  (
    'e0000000-0000-4000-8000-000000000513',
    'c0000000-0000-4000-8000-000000000512',
    'rsvp_confirmed',
    'f0000000-0000-4000-8000-000000000511',
    'confirmed:hike',
    now()
  ),
  (
    'e0000000-0000-4000-8000-000000000514',
    'c0000000-0000-4000-8000-000000000513',
    'activity_changed',
    'f0000000-0000-4000-8000-000000000511',
    'changed:hike',
    NULL
  );

-- Who isn't signed in
SET LOCAL ROLE anon;

SELECT throws_ok(
  $$select public.remove_notifications('{e0000000-0000-4000-8000-000000000511}')$$,
  '42501',
  NULL,
  'someone signed out can''t remove alerts'
);

SELECT throws_ok('select public.clear_read_notifications()', '42501', NULL, 'or clear them');

RESET ROLE;

-- Rae
SET LOCAL ROLE authenticated;

SELECT set_config(
  'request.jwt.claims',
  '{"sub": "c0000000-0000-4000-8000-000000000512", "email": "rae@byui.edu"}',
  TRUE
);

SELECT results_eq(
  $$select public.remove_notifications(
    '{e0000000-0000-4000-8000-000000000511, e0000000-0000-4000-8000-000000000514}'
  )$$,
  $$values (1)$$,
  'a member removes their own alert, and not someone else''s'
);

SELECT results_eq(
  $$select removed_at is not null, read_at is not null from public.notifications
  where id = 'e0000000-0000-4000-8000-000000000511'$$,
  $$values (true, true)$$,
  'removing a new alert marks it read too'
);

SELECT results_eq(
  'select unread_count from public.get_session_context()',
  $$values (1)$$,
  'so the badge counts only the reminder'
);

SELECT results_eq(
  $$select public.remove_notifications('{e0000000-0000-4000-8000-000000000511}')$$,
  $$values (0)$$,
  'removing it again changes nothing'
);

SELECT results_eq(
  'select public.clear_read_notifications()',
  $$values (1)$$,
  'Clear removes the read confirmation'
);

SELECT results_eq(
  $$select type from public.notifications where removed_at is null$$,
  $$values ('reminder')$$,
  'and leaves the new reminder'
);

SELECT throws_ok(
  'update public.notifications set removed_at = null',
  '42501',
  NULL,
  'members bring alerts back only through the functions'
);

-- The reminder, once it's removed, isn't sent again.
SELECT results_eq(
  $$select public.remove_notifications('{e0000000-0000-4000-8000-000000000512}')$$,
  $$values (1)$$,
  'she removes the reminder'
);

RESET ROLE;

SELECT results_eq(
  $$select removed_at is null from public.notifications
  where id = 'e0000000-0000-4000-8000-000000000514'$$,
  $$values (true)$$,
  'Ron''s alert is still there'
);

-- Other activities, such as the seed's, are hidden until the test rolls back, so only the hike is
-- due.
UPDATE public.activities
SET hidden_at = now()
WHERE id != 'f0000000-0000-4000-8000-000000000511' AND hidden_at IS NULL;

SELECT results_eq(
  $$select private.send_reminders(
    (select private.reminder_at(starts_at, timezone) from public.activities
    where id = 'f0000000-0000-4000-8000-000000000511')
  )$$,
  $$values (1)$$,
  'when the hike''s reminders go, only Ron, who had none, gets one'
);

SELECT results_eq(
  $$select removed_at is not null from public.notifications
  where id = 'e0000000-0000-4000-8000-000000000512'$$,
  $$values (true)$$,
  'and Rae''s stays removed'
);

-- A repeat
SELECT lives_ok(
  $$select private.notify(
    '{c0000000-0000-4000-8000-000000000512}',
    'activity_changed',
    'f0000000-0000-4000-8000-000000000511',
    '{"title": "Sunrise hike"}',
    'changed:hike'
  )$$,
  'the hike changes again'
);

SELECT results_eq(
  $$select removed_at is null and read_at is null from public.notifications
  where id = 'e0000000-0000-4000-8000-000000000511'$$,
  $$values (true)$$,
  'which brings Rae''s removed alert back, as new'
);

SELECT *
FROM finish();

ROLLBACK;
