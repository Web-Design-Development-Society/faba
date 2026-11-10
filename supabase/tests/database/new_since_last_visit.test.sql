-- New since your last visit (ACT-11). Run with `npm run db:test`.
BEGIN;

CREATE EXTENSION IF NOT EXISTS pgtap WITH SCHEMA extensions;

SELECT plan(7);

-- Val visits Home.
INSERT INTO auth.users
  (id, email, raw_user_meta_data)
VALUES
  ('c0000000-0000-4000-8000-000000000411', 'val@byui.edu', '{"full_name": "Val Visitor"}');

UPDATE public.profiles
SET
  guidelines_version = 1,
  guidelines_accepted_at = now()
WHERE id = 'c0000000-0000-4000-8000-000000000411';

-- Moves Val's last time on Home to `ago`.
CREATE FUNCTION pg_temp.last_seen(ago INTERVAL)
RETURNS void
LANGUAGE sql
AS $$
  UPDATE public.profile_private
  SET last_seen_at = now() - ago
  WHERE user_id = 'c0000000-0000-4000-8000-000000000411';
$$;

CREATE FUNCTION pg_temp.seen()
RETURNS TABLE (last_seen_at timestamptz, previous_visit_at timestamptz)
LANGUAGE sql
AS $$
  SELECT last_seen_at, previous_visit_at
  FROM public.profile_private
  WHERE user_id = 'c0000000-0000-4000-8000-000000000411';
$$;

SELECT set_config(
  'request.jwt.claims',
  '{"sub": "c0000000-0000-4000-8000-000000000411", "email": "val@byui.edu"}',
  TRUE
);

SET LOCAL ROLE authenticated;

SELECT results_eq(
  $$select public.record_visit()$$,
  $$values (null::timestamptz)$$,
  'a first visit has no previous one'
);

RESET ROLE;

SELECT results_eq(
  $$select * from pg_temp.seen()$$,
  $$values (now(), null::timestamptz)$$,
  'and starts one now'
);

-- Back an hour later.
SELECT pg_temp.last_seen('1 hour');

SET LOCAL ROLE authenticated;

SELECT results_eq(
  $$select public.record_visit()$$,
  $$values (now() - interval '1 hour')$$,
  'after 30 minutes away, the visit before is the previous one'
);

SELECT results_eq(
  $$select public.record_visit()$$,
  $$values (now() - interval '1 hour')$$,
  'and it stays while they browse'
);

RESET ROLE;

-- Ten minutes later, still browsing.
SELECT pg_temp.last_seen('10 minutes');

SET LOCAL ROLE authenticated;

SELECT results_eq(
  $$select public.record_visit()$$,
  $$values (now() - interval '1 hour')$$,
  'it stays within a visit'
);

RESET ROLE;

SELECT results_eq(
  $$select * from pg_temp.seen()$$,
  $$values (now(), now() - interval '1 hour')$$,
  'which keeps going'
);

SELECT set_config('request.jwt.claims', '{}', TRUE);

SET LOCAL ROLE anon;

SELECT throws_ok($$select public.record_visit()$$, '42501', NULL, 'visitors don''t have visits');

RESET ROLE;

SELECT *
FROM finish();

ROLLBACK;
