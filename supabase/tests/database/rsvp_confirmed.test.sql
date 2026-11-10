-- RSVP confirmation (NOTIF-05). Run with `npm run db:test`.
BEGIN;

CREATE EXTENSION IF NOT EXISTS pgtap WITH SCHEMA extensions;

SELECT plan(10);

-- Oda organizes a hike that welcomes guests, and Max answers.
INSERT INTO auth.users
  (id, email, raw_user_meta_data)
SELECT
  ('c0000000-0000-4000-8000-00000000036' || n)::uuid,
  name || '@byui.edu',
  jsonb_build_object('full_name', name)
FROM (
  VALUES
    (1, 'oda'),
    (2, 'max')
) AS v (n, name);

UPDATE public.profiles
SET
  guidelines_version = 1,
  guidelines_accepted_at = now()
WHERE id::text LIKE 'c0000000-0000-4000-8000-00000000036_';

INSERT INTO public.activities
  (id, organizer_id, category_id, title, starts_at, location_name, going_count, guests_allowed)
VALUES
  (
    'f0000000-0000-4000-8000-000000000361',
    'c0000000-0000-4000-8000-000000000361',
    'outdoors',
    'Sunrise hike',
    now() + INTERVAL '1 day',
    'R Mountain',
    1,
    TRUE
  );

INSERT INTO public.rsvps
  (activity_id, user_id, status)
VALUES
  ('f0000000-0000-4000-8000-000000000361', 'c0000000-0000-4000-8000-000000000361', 'going');

SET LOCAL ROLE authenticated;

SELECT set_config(
  'request.jwt.claims',
  '{"sub": "c0000000-0000-4000-8000-000000000362", "email": "max@byui.edu"}',
  TRUE
);

-- Max's confirmations, and the badge's count.
CREATE VIEW pg_temp.confirmations AS
  SELECT
    n.type,
    n.payload->>'title' AS title,
    n.payload->>'location_name' AS location_name,
    n.read_at IS NOT NULL AS read,
    n.actor_id
  FROM public.notifications AS n
  WHERE n.type = 'rsvp_confirmed';

SELECT public.rsvp('f0000000-0000-4000-8000-000000000361', 'maybe');

SELECT is_empty($$select from pg_temp.confirmations$$, 'maybe isn''t confirmed');

SELECT public.rsvp('f0000000-0000-4000-8000-000000000361', 'going');

SELECT results_eq(
  $$select type, title, location_name, read, actor_id from pg_temp.confirmations$$,
  $$values (
    'rsvp_confirmed',
    'Sunrise hike',
    'R Mountain',
    true,
    'c0000000-0000-4000-8000-000000000362'::uuid
  )$$,
  'I''m in makes a confirmation, already read'
);

SELECT results_eq(
  $$select unread_count from public.get_session_context()$$,
  $$values (0)$$,
  'so the badge doesn''t count it'
);

RESET ROLE;

UPDATE public.notifications
SET created_at = now() - INTERVAL '1 hour'
WHERE type = 'rsvp_confirmed';

SET LOCAL ROLE authenticated;

SELECT public.rsvp('f0000000-0000-4000-8000-000000000361', 'going', 2);

SELECT results_eq(
  $$select count(*)::integer, bool_and(created_at < now()) from public.notifications$$,
  $$values (1, true)$$,
  'bringing guests doesn''t confirm it again'
);

SELECT public.rsvp('f0000000-0000-4000-8000-000000000361', 'not_going');

SELECT is_empty(
  $$select from pg_temp.confirmations$$,
  'can''t make it deletes it, so Alerts doesn''t say they''re going'
);

SELECT public.rsvp('f0000000-0000-4000-8000-000000000361', 'going');

SELECT public.rsvp('f0000000-0000-4000-8000-000000000361', 'maybe');

SELECT is_empty($$select from pg_temp.confirmations$$, 'and so does changing to maybe');

SELECT public.rsvp('f0000000-0000-4000-8000-000000000361', 'going');

SELECT public.mute_activity('f0000000-0000-4000-8000-000000000361', TRUE);

SELECT public.rsvp('f0000000-0000-4000-8000-000000000361', 'maybe');

SELECT public.rsvp('f0000000-0000-4000-8000-000000000361', 'going');

SELECT results_eq(
  $$select count(*)::integer, bool_and(read) from pg_temp.confirmations$$,
  $$values (1, true)$$,
  'going again makes one, still read, even when muted'
);

-- Oda gets no confirmation for Max's RSVP.
SELECT set_config(
  'request.jwt.claims',
  '{"sub": "c0000000-0000-4000-8000-000000000361", "email": "oda@byui.edu"}',
  TRUE
);

SELECT is_empty(
  $$select from public.notifications where type = 'rsvp_confirmed'$$,
  'the organizer gets no confirmation'
);

SELECT throws_ok(
  $$select public.rsvp('f0000000-0000-4000-8000-000000000361', 'going')$$,
  '22023',
  'ORGANIZER_GOING',
  'and can''t RSVP to make one'
);

RESET ROLE;

SELECT results_eq(
  $$
    select count(*)::integer
    from public.notifications
    where type = 'rsvp_confirmed' and recipient_id = 'c0000000-0000-4000-8000-000000000362'
  $$,
  $$values (1)$$,
  'Max has one confirmation in all'
);

SELECT *
FROM finish();

ROLLBACK;
