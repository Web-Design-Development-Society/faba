-- Board activities and announcements (MOD-07). Run with `npm run db:test`.
BEGIN;

CREATE EXTENSION IF NOT EXISTS pgtap WITH SCHEMA extensions;

SELECT plan(14);

-- Ada is an admin, Mod is a moderator, and Mel and Sue are members. Sue is suspended.
INSERT INTO auth.users
  (id, email, raw_user_meta_data)
SELECT
  ('c0000000-0000-4000-8000-00000000040' || n)::uuid,
  name || '@byui.edu',
  jsonb_build_object('full_name', name)
FROM (
  VALUES
    (1, 'ada'),
    (2, 'mod'),
    (3, 'mel'),
    (4, 'sue')
) AS v (n, name);

UPDATE public.profiles
SET
  guidelines_version = 1,
  guidelines_accepted_at = now(),
  role = CASE id
    WHEN 'c0000000-0000-4000-8000-000000000401' THEN 'admin'
    WHEN 'c0000000-0000-4000-8000-000000000402' THEN 'moderator'
    ELSE 'member'
  END,
  status = CASE id
    WHEN 'c0000000-0000-4000-8000-000000000404' THEN 'suspended'
    ELSE 'active'
  END
WHERE id::text LIKE 'c0000000-0000-4000-8000-00000000040_';

INSERT INTO public.activities
  (id, organizer_id, category_id, title, starts_at, location_name)
VALUES
  (
    'f0000000-0000-4000-8000-000000000401',
    'c0000000-0000-4000-8000-000000000401',
    'food',
    'Welcome back social',
    now() + INTERVAL '7 days',
    'Hart ballroom'
  ),
  (
    'f0000000-0000-4000-8000-000000000402',
    'c0000000-0000-4000-8000-000000000402',
    'games',
    'Chess club',
    now() + INTERVAL '7 days',
    'Library'
  ),
  (
    'f0000000-0000-4000-8000-000000000403',
    'c0000000-0000-4000-8000-000000000401',
    'food',
    'Last year''s social',
    now() - INTERVAL '7 days',
    'Hart ballroom'
  );

-- Signs in as Ada (1), Mod (2) or Mel (3).
CREATE FUNCTION pg_temp.sign_in(member text)
RETURNS void
LANGUAGE sql
AS $$
  SELECT set_config(
    'request.jwt.claims',
    json_build_object(
      'sub',
      'c0000000-0000-4000-8000-00000000040' || member,
      'email',
      member || '@byui.edu'
    )::text,
    TRUE
  );
$$;

GRANT EXECUTE ON FUNCTION pg_temp.sign_in(text) TO authenticated;

SET LOCAL ROLE authenticated;

SELECT pg_temp.sign_in('2');

SELECT throws_ok(
  $$select public.set_board_activity('f0000000-0000-4000-8000-000000000402', true)$$,
  '42501',
  'NOT_ADMIN',
  'a moderator can''t mark one'
);

SELECT pg_temp.sign_in('1');

SELECT throws_ok(
  $$select public.set_board_activity('f0000000-0000-4000-8000-000000000402', true)$$,
  '42501',
  'NOT_ORGANIZER',
  'an admin can''t mark one they don''t organize'
);

SELECT throws_ok(
  $$select public.announce_activity('f0000000-0000-4000-8000-000000000401')$$,
  '22023',
  'NOT_BOARD_ACTIVITY',
  'or announce one that isn''t a board activity'
);

SELECT public.set_board_activity('f0000000-0000-4000-8000-000000000401', TRUE);

SELECT public.set_board_activity('f0000000-0000-4000-8000-000000000401', TRUE);

SELECT results_eq(
  $$select is_board_activity from public.activities where id = 'f0000000-0000-4000-8000-000000000401'$$,
  $$values (true)$$,
  'an admin marks one they organize'
);

SELECT pg_temp.sign_in('3');

SELECT results_eq(
  $$select is_board_activity from public.activities where id = 'f0000000-0000-4000-8000-000000000401'$$,
  $$values (true)$$,
  'and members see it'
);

SELECT throws_ok(
  $$select public.announce_activity('f0000000-0000-4000-8000-000000000401')$$,
  '42501',
  'NOT_ADMIN',
  'only admins announce'
);

SELECT pg_temp.sign_in('1');

SELECT results_eq(
  $$select public.announce_activity('f0000000-0000-4000-8000-000000000401') >= 2$$,
  $$values (true)$$,
  'announcing tells the members'
);

SELECT throws_ok(
  $$select public.announce_activity('f0000000-0000-4000-8000-000000000401')$$,
  '22023',
  'ALREADY_ANNOUNCED',
  'once'
);

SELECT pg_temp.sign_in('3');

SELECT results_eq(
  $$
    select type, payload ->> 'title', read_at is null, actor_id
    from public.notifications
    where activity_id = 'f0000000-0000-4000-8000-000000000401'
  $$,
  $$values (
    'board_announcement',
    'Welcome back social',
    true,
    'c0000000-0000-4000-8000-000000000401'::uuid
  )$$,
  'each member gets one, unread'
);

SELECT pg_temp.sign_in('1');

SELECT public.set_board_activity('f0000000-0000-4000-8000-000000000403', TRUE);

SELECT throws_ok(
  $$select public.announce_activity('f0000000-0000-4000-8000-000000000403')$$,
  '22023',
  'ANNOUNCE_TOO_LATE',
  'a past one can''t be announced'
);

RESET ROLE;

SELECT results_eq(
  $$
    select count(*)::integer
    from public.notifications
    where
      activity_id = 'f0000000-0000-4000-8000-000000000401'
      and recipient_id in (
        'c0000000-0000-4000-8000-000000000401',
        'c0000000-0000-4000-8000-000000000404'
      )
  $$,
  $$values (0)$$,
  'not the admin, or a suspended member'
);

SELECT results_eq(
  $$
    select count(*)::integer
    from public.notifications
    where activity_id = 'f0000000-0000-4000-8000-000000000401'
  $$,
  $$
    select count(*)::integer
    from public.profiles
    where status = 'active' and id != 'c0000000-0000-4000-8000-000000000401'
  $$,
  'but every other active member'
);

SELECT results_eq(
  $$
    select action, metadata ->> 'board', actor_id
    from private.audit_log
    where target_id = 'f0000000-0000-4000-8000-000000000401' and action = 'set_board_activity'
  $$,
  $$values ('set_board_activity', 'true', 'c0000000-0000-4000-8000-000000000401'::uuid)$$,
  'marking it is audit-logged, once'
);

SELECT results_eq(
  $$
    select action, actor_id
    from private.audit_log
    where target_id = 'f0000000-0000-4000-8000-000000000401' and action = 'announce_activity'
  $$,
  $$values ('announce_activity', 'c0000000-0000-4000-8000-000000000401'::uuid)$$,
  'and so is announcing it'
);

SELECT *
FROM finish();

ROLLBACK;
