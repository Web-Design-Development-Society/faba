-- Telling attendees about a new time or place (NOTIF-02). Run with `npm run db:test`.
BEGIN;

CREATE EXTENSION IF NOT EXISTS pgtap WITH SCHEMA extensions;

SELECT plan(9);

-- Ora organizes board games. Gia is going, May is a maybe, Nat can't make it, and Sue is going but
-- suspended.
INSERT INTO auth.users
  (id, email, raw_user_meta_data)
SELECT
  ('c0000000-0000-4000-8000-00000000028' || n)::uuid,
  name || '@byui.edu',
  jsonb_build_object('full_name', name)
FROM (
  VALUES
    (1, 'ora'),
    (2, 'gia'),
    (3, 'may'),
    (4, 'nat'),
    (5, 'sue')
) AS v (n, name);

UPDATE public.profiles
SET
  guidelines_version = 1,
  guidelines_accepted_at = now(),
  status = CASE id WHEN 'c0000000-0000-4000-8000-000000000285' THEN 'suspended' ELSE 'active' END
WHERE id::text LIKE 'c0000000-0000-4000-8000-00000000028_';

INSERT INTO public.activities
  (id, organizer_id, category_id, title, starts_at, location_name, going_count, maybe_count)
VALUES
  (
    'f0000000-0000-4000-8000-000000000281',
    'c0000000-0000-4000-8000-000000000281',
    'games',
    'Board games',
    '2026-12-04 19:00-07',
    'Library',
    3,
    1
  );

INSERT INTO public.rsvps
  (activity_id, user_id, status)
SELECT
  'f0000000-0000-4000-8000-000000000281',
  ('c0000000-0000-4000-8000-00000000028' || n)::uuid,
  status
FROM (
  VALUES
    ('1', 'going'),
    ('2', 'going'),
    ('3', 'maybe'),
    ('4', 'not_going'),
    ('5', 'going')
) AS v (n, status);

SET LOCAL ROLE authenticated;

SELECT set_config(
  'request.jwt.claims',
  '{"sub": "c0000000-0000-4000-8000-000000000281", "email": "ora@byui.edu"}',
  TRUE
);

-- Ora's edits
CREATE FUNCTION pg_temp.edit(patch jsonb)
RETURNS void
LANGUAGE sql
AS $$
  SELECT public.update_activity(
    'f0000000-0000-4000-8000-000000000281',
    patch,
    (SELECT version FROM public.activities WHERE id = 'f0000000-0000-4000-8000-000000000281')
  );
$$;

SELECT pg_temp.edit('{"starts_at": "2026-12-04 19:30-07"}');

RESET ROLE;

-- What each recipient has, read as the database owner.
CREATE VIEW pg_temp.sent AS
  SELECT
    right(recipient_id::text, 1) AS who,
    payload->'before'->>'location_name' AS was_at,
    payload->'after'->>'location_name' AS now_at,
    (payload->'before'->>'starts_at')::timestamptz AS was,
    (payload->'after'->>'starts_at')::timestamptz AS now,
    read_at IS NULL AS unread
  FROM public.notifications
  WHERE activity_id = 'f0000000-0000-4000-8000-000000000281' AND type = 'activity_changed';

SELECT results_eq(
  'select who, was, now, unread from pg_temp.sent order by who',
  $$values
    ('2', '2026-12-04 19:00-07'::timestamptz, '2026-12-04 19:30-07'::timestamptz, true),
    ('3', '2026-12-04 19:00-07'::timestamptz, '2026-12-04 19:30-07'::timestamptz, true)$$,
  'a new time notifies those going or maybe, not the editor, can''t-make-its or the suspended'
);

UPDATE public.notifications
SET read_at = now()
WHERE recipient_id = 'c0000000-0000-4000-8000-000000000282';

SET LOCAL ROLE authenticated;

SELECT pg_temp.edit('{"location_name": "Hart courts"}');

RESET ROLE;

SELECT results_eq(
  'select who, was, now, was_at, now_at, unread from pg_temp.sent order by who',
  $$values
    (
      '2',
      '2026-12-04 19:00-07'::timestamptz,
      '2026-12-04 19:30-07'::timestamptz,
      'Library',
      'Hart courts',
      true
    ),
    (
      '3',
      '2026-12-04 19:00-07'::timestamptz,
      '2026-12-04 19:30-07'::timestamptz,
      'Library',
      'Hart courts',
      true
    )$$,
  'another change within 10 minutes is the same notification, from where it started, unread again'
);

SET LOCAL ROLE authenticated;

SELECT lives_ok(
  $$select pg_temp.edit('{"description": "Bring a game you love."}')$$,
  'the organizer changes only the description'
);

RESET ROLE;

SELECT results_eq(
  'select count(*)::integer from pg_temp.sent',
  $$values (2)$$,
  'which doesn''t notify'
);

SELECT results_eq(
  'select count(*)::integer from public.notifications where actor_id = ''c0000000-0000-4000-8000-000000000281''',
  $$values (2)$$,
  'and each says who changed it'
);

-- Later
UPDATE public.notifications
SET created_at = now() - INTERVAL '11 minutes'
WHERE activity_id = 'f0000000-0000-4000-8000-000000000281';

SET LOCAL ROLE authenticated;

SELECT lives_ok(
  $$select pg_temp.edit('{"ends_at": "2026-12-04 21:30-07"}')$$,
  'a change more than 10 minutes later'
);

RESET ROLE;

SELECT results_eq(
  'select count(*)::integer from pg_temp.sent',
  $$values (4)$$,
  'is a new notification'
);

SELECT results_eq(
  $$select payload -> 'after' ->> 'ends_at' is not null from public.notifications
  where activity_id = 'f0000000-0000-4000-8000-000000000281' order by created_at desc limit 1$$,
  $$values (true)$$,
  'with the new end time'
);

SET LOCAL ROLE authenticated;

SELECT set_config(
  'request.jwt.claims',
  '{"sub": "c0000000-0000-4000-8000-000000000282", "email": "gia@byui.edu"}',
  TRUE
);

SELECT results_eq(
  'select unread_count from public.get_session_context()',
  $$values (2)$$,
  'and an attendee has both unread'
);

SELECT *
FROM finish();

ROLLBACK;
