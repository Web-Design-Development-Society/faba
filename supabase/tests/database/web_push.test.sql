-- Web Push (NOTIF-20). Run with `npm run db:test`.
BEGIN;

CREATE EXTENSION IF NOT EXISTS pgtap WITH SCHEMA extensions;

SELECT plan(24);

-- Pia turns push on. Ned shares her computer later.
INSERT INTO auth.users
  (id, email, raw_user_meta_data)
VALUES
  ('c0000000-0000-4000-8000-000000002001', 'pia@byui.edu', '{"full_name": "Pia Member"}'),
  ('c0000000-0000-4000-8000-000000002002', 'ned@byui.edu', '{"full_name": "Ned Member"}');

UPDATE public.profiles
SET
  guidelines_version = 1,
  guidelines_accepted_at = now()
WHERE id BETWEEN 'c0000000-0000-4000-8000-000000002001' AND 'c0000000-0000-4000-8000-000000002002';

CREATE TEMPORARY TABLE keys AS
  SELECT 'B' || repeat('A', 86) AS p256dh, repeat('A', 22) AS secret;

GRANT SELECT ON keys TO authenticated;

SET LOCAL ROLE authenticated;

SELECT set_config(
  'request.jwt.claims',
  '{"sub": "c0000000-0000-4000-8000-000000002001", "email": "pia@byui.edu"}',
  TRUE
);

-- The in-app switch for subs needed failed before, since the preferences didn't know the type.
SELECT lives_ok(
  $$select public.set_notification_preferences(array['sub_needed'])$$,
  'a member can turn subs needed off in the app'
);

SELECT lives_ok($$select public.set_notification_preferences(array[]::text[])$$, 'and on again');

SELECT lives_ok(
  $$select public.save_push_subscription('https://push.example/pia-phone', p256dh, secret) from keys$$,
  'a member turns push on for a device'
);

SELECT results_eq(
  $$select endpoint from public.push_subscriptions$$,
  $$values ('https://push.example/pia-phone')$$,
  'she can see her device'
);

SELECT throws_ok(
  $$select public.claim_push_deliveries()$$,
  '42501',
  NULL,
  'a member cannot claim pushes'
);

RESET ROLE;

-- Urgent types push by default. Others stay in the app.
SELECT private.notify(
  ARRAY['c0000000-0000-4000-8000-000000002001']::uuid[],
  'activity_changed',
  NULL,
  '{"title": "Hike"}',
  'push-changed'
);

SELECT private.notify(
  ARRAY['c0000000-0000-4000-8000-000000002001']::uuid[],
  'new_attendees',
  NULL,
  '{"count": 2}',
  'push-new-attendees'
);

SELECT results_eq(
  $$select n.type from public.notification_deliveries as d join public.notifications as n on n.id = d.notification_id where d.status = 'pending'$$,
  $$values ('activity_changed')$$,
  'only the urgent notification is queued to push'
);

-- She turns new attendees on, and changes off. Cancellations can't be turned off.
SET LOCAL ROLE authenticated;

SELECT lives_ok(
  $$select public.set_push_preferences(array['new_attendees'], array['activity_changed', 'activity_cancelled'])$$,
  'a member chooses which types push'
);

SELECT results_eq(
  $$select type, enabled from public.notification_preferences where channel = 'push' order by type$$,
  $$values ('activity_changed', FALSE), ('new_attendees', TRUE)$$,
  'only choices that differ from the default are stored'
);

RESET ROLE;

DELETE FROM public.notification_deliveries;

SELECT private.notify(
  ARRAY['c0000000-0000-4000-8000-000000002001']::uuid[],
  'activity_changed',
  NULL,
  '{"title": "Run"}',
  'push-changed-off'
);

SELECT private.notify(
  ARRAY['c0000000-0000-4000-8000-000000002001']::uuid[],
  'new_attendees',
  NULL,
  '{"count": 1}',
  'push-new-on'
);

SELECT private.notify(
  ARRAY['c0000000-0000-4000-8000-000000002001']::uuid[],
  'activity_cancelled',
  NULL,
  '{"title": "Swim"}',
  'push-cancelled'
);

SELECT results_eq(
  $$select n.type from public.notification_deliveries as d join public.notifications as n on n.id = d.notification_id order by n.type$$,
  $$values ('activity_cancelled'), ('new_attendees')$$,
  'her choices apply, and cancellations always push'
);

-- The sender claims what's due.
SET LOCAL ROLE service_role;

SELECT results_eq(
  $$select type, endpoint, attempts from public.claim_push_deliveries() order by type$$,
  $$values ('activity_cancelled', 'https://push.example/pia-phone', 1), ('new_attendees', 'https://push.example/pia-phone', 1)$$,
  'the sender claims each due push with its device'
);

SELECT is_empty(
  $$select * from public.claim_push_deliveries()$$,
  'a claimed push is not claimed again right away'
);

SELECT lives_ok(
  $$select public.finish_push_delivery(d.id, 'sent') from public.notification_deliveries as d join public.notifications as n on n.id = d.notification_id where n.type = 'activity_cancelled'$$,
  'the sender reports a push sent'
);

SELECT lives_ok(
  $$select public.finish_push_delivery(d.id, 'retry', 'push service said 503') from public.notification_deliveries as d join public.notifications as n on n.id = d.notification_id where n.type = 'new_attendees'$$,
  'the sender reports a push to try again'
);

RESET ROLE;

SELECT results_eq(
  $$select n.type, d.status, d.next_attempt_at > now(), d.last_error from public.notification_deliveries as d join public.notifications as n on n.id = d.notification_id order by n.type$$,
  $$values ('activity_cancelled', 'sent', TRUE, NULL::text), ('new_attendees', 'pending', TRUE, 'push service said 503')$$,
  'a sent push is done, and a retry waits'
);

SELECT isnt(
  (
    SELECT last_sent_at
    FROM public.push_subscriptions
    WHERE endpoint = 'https://push.example/pia-phone'
  ),
  NULL,
  'the device remembers its last push'
);

-- After five tries, a push gives up.
UPDATE public.notification_deliveries SET attempts = 5 WHERE status = 'pending';

SET LOCAL ROLE service_role;

SELECT public.finish_push_delivery(d.id, 'retry', 'still 503')
FROM public.notification_deliveries AS d
WHERE d.status = 'pending';

RESET ROLE;

SELECT results_eq(
  $$select status from public.notification_deliveries as d join public.notifications as n on n.id = d.notification_id where n.type = 'new_attendees'$$,
  $$values ('failed')$$,
  'a push gives up after its fifth try'
);

-- A repeat of a notification pushes again. The first one was an hour ago (a repeat in the same
-- transaction would have the same time, since now() is the transaction's start).
ALTER TABLE public.notifications DISABLE TRIGGER notifications_queue_push_again;

UPDATE public.notifications
SET created_at = now() - INTERVAL '1 hour'
WHERE type = 'activity_cancelled';

ALTER TABLE public.notifications ENABLE TRIGGER notifications_queue_push_again;

SELECT private.notify(
  ARRAY['c0000000-0000-4000-8000-000000002001']::uuid[],
  'activity_cancelled',
  NULL,
  '{"title": "Swim"}',
  'push-cancelled'
);

SELECT results_eq(
  $$select status, attempts from public.notification_deliveries as d join public.notifications as n on n.id = d.notification_id where n.type = 'activity_cancelled'$$,
  $$values ('pending', 0)$$,
  'a repeated notification is queued to push again'
);

-- Read in the app first, so it isn't pushed.
UPDATE public.notifications SET read_at = now() WHERE type = 'activity_cancelled';

SET LOCAL ROLE service_role;

SELECT is_empty(
  $$select * from public.claim_push_deliveries()$$,
  'a notification already read is not pushed'
);

RESET ROLE;

SELECT results_eq(
  $$select status from public.notification_deliveries as d join public.notifications as n on n.id = d.notification_id where n.type = 'activity_cancelled'$$,
  $$values ('skipped')$$,
  'and its push is skipped'
);

-- Ned signs in on Pia's computer and turns push on: the device is his now.
SET LOCAL ROLE authenticated;

SELECT set_config(
  'request.jwt.claims',
  '{"sub": "c0000000-0000-4000-8000-000000002002", "email": "ned@byui.edu"}',
  TRUE
);

SELECT is_empty(
  $$select * from public.push_subscriptions$$,
  'a member cannot see someone else''s devices'
);

SELECT public.save_push_subscription('https://push.example/pia-phone', p256dh, secret) FROM keys;

RESET ROLE;

SELECT results_eq(
  $$select user_id from public.push_subscriptions where endpoint = 'https://push.example/pia-phone'$$,
  $$values ('c0000000-0000-4000-8000-000000002002'::uuid)$$,
  'a device belongs to whoever turned push on last'
);

-- Ned turns push on for 11 devices, and keeps the newest 10.
SET LOCAL ROLE authenticated;

SELECT public.save_push_subscription('https://push.example/ned-' || n, p256dh, secret)
FROM
  keys,
  generate_series(1, 11) AS n;

RESET ROLE;

SELECT results_eq(
  $$select count(*)::INTEGER from public.push_subscriptions where user_id = 'c0000000-0000-4000-8000-000000002002'$$,
  $$values (10)$$,
  'a member keeps at most 10 devices'
);

-- The push service says a device is gone: it's forgotten.
SELECT private.notify(
  ARRAY['c0000000-0000-4000-8000-000000002002']::uuid[],
  'reminder',
  NULL,
  '{"title": "Lunch"}',
  'push-gone'
);

SET LOCAL ROLE service_role;

SELECT public.finish_push_delivery(d.delivery_id, 'gone')
FROM public.claim_push_deliveries() AS d
WHERE d.endpoint = 'https://push.example/ned-11';

RESET ROLE;

SELECT is_empty(
  $$select * from public.push_subscriptions where endpoint = 'https://push.example/ned-11'$$,
  'a device the push service says is gone is forgotten'
);

-- Ned turns push off on one device.
SET LOCAL ROLE authenticated;

SELECT public.remove_push_subscription('https://push.example/ned-10');

SELECT results_eq(
  $$select count(*)::INTEGER from public.push_subscriptions$$,
  $$values (8)$$,
  'a member turns push off for a device'
);

RESET ROLE;

SELECT * FROM finish();

ROLLBACK;
