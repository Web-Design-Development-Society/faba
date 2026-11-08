-- Telling attendees when an activity is cancelled or back on (NOTIF-03). Run with
-- `npm run db:test`.
BEGIN;

CREATE EXTENSION IF NOT EXISTS pgtap WITH SCHEMA extensions;

SELECT plan(8);

-- Ora, Ivy (no longer at BYU-Idaho) and Ola each organize an activity. Gia is going to all three,
-- May is a maybe to Ora's, and Nat can't make it. Mo moderates.
INSERT INTO auth.users
  (id, email, raw_user_meta_data)
SELECT
  ('c0000000-0000-4000-8000-00000000029' || n)::uuid,
  name || '@byui.edu',
  jsonb_build_object('full_name', name)
FROM (
  VALUES
    (1, 'ora'),
    (2, 'gia'),
    (3, 'may'),
    (4, 'nat'),
    (5, 'ivy'),
    (6, 'ola'),
    (7, 'mo')
) AS v (n, name);

UPDATE public.profiles
SET
  guidelines_version = 1,
  guidelines_accepted_at = now(),
  status = CASE id WHEN 'c0000000-0000-4000-8000-000000000295' THEN 'ineligible' ELSE 'active' END,
  role = CASE id WHEN 'c0000000-0000-4000-8000-000000000297' THEN 'moderator' ELSE 'member' END
WHERE id::text LIKE 'c0000000-0000-4000-8000-00000000029_';

INSERT INTO public.activities
  (id, organizer_id, category_id, title, starts_at, location_name, going_count, maybe_count)
SELECT
  ('f0000000-0000-4000-8000-00000000029' || n)::uuid,
  ('c0000000-0000-4000-8000-00000000029' || organizer)::uuid,
  'games',
  title,
  now() + INTERVAL '1 day',
  'Here',
  going,
  maybe
FROM (
  VALUES
    (1, 1, 'Board games', 2, 1),
    (2, 5, 'Ivy''s hike', 1, 0),
    (3, 6, 'Ola''s lunch', 2, 0)
) AS v (n, organizer, title, going, maybe);

INSERT INTO public.rsvps
  (activity_id, user_id, status)
SELECT
  ('f0000000-0000-4000-8000-00000000029' || activity)::uuid,
  ('c0000000-0000-4000-8000-00000000029' || member)::uuid,
  status
FROM (
  VALUES
    ('1', '1', 'going'),
    ('1', '2', 'going'),
    ('1', '3', 'maybe'),
    ('1', '4', 'not_going'),
    ('2', '2', 'going'),
    ('3', '6', 'going'),
    ('3', '2', 'going')
) AS v (activity, member, status);

-- What each recipient has about an activity, read as the database owner.
CREATE FUNCTION pg_temp.sent(activity text)
RETURNS TABLE (who text, type text, reason text, actor text)
LANGUAGE sql
AS $$
  SELECT right(recipient_id::text, 1), type, payload->>'reason', right(actor_id::text, 1)
  FROM public.notifications
  WHERE activity_id = ('f0000000-0000-4000-8000-00000000029' || activity)::uuid
  ORDER BY created_at, type, recipient_id;
$$;

-- Ora cancels, then restores.
SET LOCAL ROLE authenticated;

SELECT set_config(
  'request.jwt.claims',
  '{"sub": "c0000000-0000-4000-8000-000000000291", "email": "ora@byui.edu"}',
  TRUE
);

SELECT public.cancel_activity('f0000000-0000-4000-8000-000000000291', 'Snowed in');

SELECT public.cancel_activity('f0000000-0000-4000-8000-000000000291', 'Snowed in');

RESET ROLE;

SELECT results_eq(
  $$select who, type, reason, actor from pg_temp.sent('1')$$,
  $$values
    ('2', 'activity_cancelled', 'Snowed in', '1'),
    ('3', 'activity_cancelled', 'Snowed in', '1')$$,
  'cancelling tells those going or maybe, with the reason, once, but not the organizer or a can''t-make-it'
);

SET LOCAL ROLE authenticated;

SELECT public.restore_activity('f0000000-0000-4000-8000-000000000291');

RESET ROLE;

SELECT results_eq(
  $$select who, type from pg_temp.sent('1') where type = 'activity_restored'$$,
  $$values ('2', 'activity_restored'), ('3', 'activity_restored')$$,
  'restoring tells them it''s back on'
);

SELECT results_eq(
  $$select count(*)::integer from public.notifications
  where activity_id = 'f0000000-0000-4000-8000-000000000291' and read_at is null$$,
  $$values (4)$$,
  'and both are unread'
);

-- Mo cancels Ivy's hike.
SET LOCAL ROLE authenticated;

SELECT set_config(
  'request.jwt.claims',
  '{"sub": "c0000000-0000-4000-8000-000000000297", "email": "mo@byui.edu"}',
  TRUE
);

SELECT lives_ok(
  $$select public.moderate_cancel_activity('f0000000-0000-4000-8000-000000000292', 'Nobody can host')$$,
  'a moderator cancels an ineligible organizer''s activity'
);

RESET ROLE;

SELECT results_eq(
  $$select who, type, reason, actor from pg_temp.sent('2')$$,
  $$values ('2', 'activity_cancelled', 'Its organizer is no longer active.', '7')$$,
  'which tells those going'
);

-- Ola deletes her account.
SET LOCAL ROLE authenticated;

SELECT set_config(
  'request.jwt.claims',
  '{"sub": "c0000000-0000-4000-8000-000000000296", "email": "ola@byui.edu"}',
  TRUE
);

SELECT lives_ok('select public.delete_my_account()', 'an organizer deletes their account');

RESET ROLE;

SELECT results_eq(
  $$select who, type, reason from pg_temp.sent('3')$$,
  $$values ('2', 'activity_cancelled', 'Its organizer left FABA.')$$,
  'and those going to their activities hear it''s cancelled'
);

SELECT function_privs_are(
  'private',
  'notify_attendees',
  ARRAY['uuid', 'text', 'jsonb'],
  'authenticated',
  ARRAY[]::text[],
  'members can''t notify attendees directly'
);

SELECT *
FROM finish();

ROLLBACK;
