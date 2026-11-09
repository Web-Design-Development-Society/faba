-- Notifications (NOTIF-01). Run with `npm run db:test`.
BEGIN;

CREATE EXTENSION IF NOT EXISTS pgtap WITH SCHEMA extensions;

SELECT plan(15);

-- Ola organizes a hike, and Nan and Ned are going.
INSERT INTO auth.users
  (id, email, raw_user_meta_data)
SELECT
  ('c0000000-0000-4000-8000-00000000027' || n)::uuid,
  name || '@byui.edu',
  jsonb_build_object('full_name', name)
FROM (
  VALUES
    (1, 'ola'),
    (2, 'nan'),
    (3, 'ned')
) AS v (n, name);

UPDATE public.profiles
SET
  guidelines_version = 1,
  guidelines_accepted_at = now()
WHERE id::text LIKE 'c0000000-0000-4000-8000-00000000027_';

INSERT INTO public.activities
  (id, organizer_id, category_id, title, starts_at, location_name)
VALUES
  (
    'f0000000-0000-4000-8000-000000000271',
    'c0000000-0000-4000-8000-000000000271',
    'outdoors',
    'Sunrise hike',
    now() + INTERVAL '1 day',
    'R Mountain'
  );

-- Made as a domain function would, by the database owner.
SELECT results_eq(
  $$select private.notify(
    '{c0000000-0000-4000-8000-000000000272, c0000000-0000-4000-8000-000000000273}',
    'activity_changed',
    'f0000000-0000-4000-8000-000000000271',
    '{"title": "Sunrise hike", "starts_at": "7:00 AM"}',
    'changed:hike:1'
  )$$,
  $$values (2)$$,
  'a notification is made for each recipient'
);

SELECT results_eq(
  $$select private.notify(
    '{c0000000-0000-4000-8000-000000000272}',
    'activity_changed',
    'f0000000-0000-4000-8000-000000000271',
    '{"title": "Sunrise hike", "starts_at": "7:30 AM"}',
    'changed:hike:1'
  )$$,
  $$values (1)$$,
  'a repeat with the same key'
);

SELECT results_eq(
  $$select count(*)::integer, max(payload ->> 'starts_at') from public.notifications
  where recipient_id = 'c0000000-0000-4000-8000-000000000272'$$,
  $$values (1, '7:30 AM')$$,
  'updates the one the recipient had'
);

SELECT lives_ok(
  $$select private.notify(
    '{c0000000-0000-4000-8000-000000000272, c0000000-0000-4000-8000-000000000272}',
    'reminder',
    'f0000000-0000-4000-8000-000000000271',
    '{"title": "Sunrise hike"}'
  )$$,
  'a recipient named twice gets one'
);

-- Nan
SET LOCAL ROLE authenticated;

SELECT set_config(
  'request.jwt.claims',
  '{"sub": "c0000000-0000-4000-8000-000000000272", "email": "nan@byui.edu"}',
  TRUE
);

SELECT results_eq(
  $$select type from public.notifications order by type$$,
  $$values ('activity_changed'), ('reminder')$$,
  'a member reads their own notifications, and nobody else''s'
);

SELECT results_eq(
  'select unread_count from public.get_session_context()',
  $$values (2)$$,
  'and their session has the unread count'
);

SELECT results_eq(
  $$select public.mark_notifications_read(array(
    select id from public.notifications where type = 'reminder'
  ))$$,
  $$values (1)$$,
  'they mark one read'
);

SELECT results_eq('select public.mark_notifications_read()', $$values (1)$$, 'then the rest');

SELECT results_eq(
  'select unread_count from public.get_session_context()',
  $$values (0)$$,
  'and none are unread'
);

SELECT throws_ok(
  'update public.notifications set read_at = null',
  '42501',
  NULL,
  'members change notifications only through the functions'
);

RESET ROLE;

SELECT lives_ok(
  $$select private.notify(
    '{c0000000-0000-4000-8000-000000000272}',
    'activity_changed',
    'f0000000-0000-4000-8000-000000000271',
    '{"title": "Sunrise hike", "starts_at": "8:00 AM"}',
    'changed:hike:1'
  )$$,
  'another repeat'
);

SELECT results_eq(
  $$select read_at is null from public.notifications
  where recipient_id = 'c0000000-0000-4000-8000-000000000272' and type = 'activity_changed'$$,
  $$values (true)$$,
  'brings a read notification back as unread'
);

-- Keeping
DELETE FROM public.activities
WHERE id = 'f0000000-0000-4000-8000-000000000271';

INSERT INTO public.notifications
  (recipient_id, type, payload, created_at)
VALUES
  (
    'c0000000-0000-4000-8000-000000000273',
    'reminder',
    '{"title": "Last spring"}',
    now() - INTERVAL '91 days'
  );

SELECT results_eq(
  $$select private.purge_old_data()$$,
  $$values (1)$$,
  'notifications older than 90 days are deleted'
);

SELECT results_eq(
  $$select count(*)::integer, count(activity_id)::integer from public.notifications
  where recipient_id::text like 'c0000000-0000-4000-8000-00000000027_'$$,
  $$values (3, 0)$$,
  'and newer ones stay, even once their activity is gone'
);

SELECT results_eq(
  $$select schedule, command from cron.job where jobname = 'purge-old-data'$$,
  $$values ('30 10 * * *'::text, 'select private.purge_old_data()'::text)$$,
  'every night'
);

SELECT *
FROM finish();

ROLLBACK;
