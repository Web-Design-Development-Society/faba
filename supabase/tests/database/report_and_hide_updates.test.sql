-- Reporting and hiding organizer updates (NOTIF-04, FR-REP-3). Run with `npm run db:test`.
BEGIN;

CREATE EXTENSION IF NOT EXISTS pgtap WITH SCHEMA extensions;

SELECT plan(15);

-- Otto organizes a hike and posts two updates, one of them spam. Gwen reports it, and Mo
-- moderates.
INSERT INTO auth.users
  (id, email, raw_user_meta_data)
SELECT
  ('c0000000-0000-4000-8000-00000000033' || n)::uuid,
  name || '@byui.edu',
  jsonb_build_object('full_name', name)
FROM (
  VALUES
    (1, 'otto'),
    (2, 'gwen'),
    (3, 'mo')
) AS v (n, name);

UPDATE public.profiles
SET
  guidelines_version = 1,
  guidelines_accepted_at = now(),
  role = CASE id WHEN 'c0000000-0000-4000-8000-000000000333' THEN 'moderator' ELSE 'member' END
WHERE id::text LIKE 'c0000000-0000-4000-8000-00000000033_';

INSERT INTO public.activities
  (id, organizer_id, category_id, title, starts_at, location_name)
VALUES
  (
    'f0000000-0000-4000-8000-000000000331',
    'c0000000-0000-4000-8000-000000000331',
    'outdoors',
    'Hike',
    now() + INTERVAL '1 day',
    'R Mountain trailhead'
  );

INSERT INTO public.activity_updates
  (id, activity_id, author_id, body)
VALUES
  (
    'e0000000-0000-4000-8000-000000000331',
    'f0000000-0000-4000-8000-000000000331',
    'c0000000-0000-4000-8000-000000000331',
    'Bring a headlamp!'
  ),
  (
    'e0000000-0000-4000-8000-000000000332',
    'f0000000-0000-4000-8000-000000000331',
    'c0000000-0000-4000-8000-000000000331',
    'Cheap tickets at example.com'
  );

CREATE FUNCTION pg_temp.as_member(n INTEGER)
RETURNS void
LANGUAGE sql
AS $$
  SELECT set_config(
    'request.jwt.claims',
    jsonb_build_object(
      'sub',
      'c0000000-0000-4000-8000-00000000033' || n,
      'email',
      'm@byui.edu'
    )::text,
    TRUE
  );
$$;

GRANT EXECUTE ON ALL FUNCTIONS IN SCHEMA pg_temp TO authenticated;

SET LOCAL ROLE authenticated;

SELECT pg_temp.as_member(2);

SELECT lives_ok(
  $$select public.report_content(
    'activity_update', 'e0000000-0000-4000-8000-000000000332', 'spam', 'Selling tickets'
  )$$,
  'a member reports an update'
);

SELECT throws_ok(
  $$select public.moderate_hide_update('e0000000-0000-4000-8000-000000000332', 'Spam')$$,
  '42501',
  'NOT_MODERATOR',
  'members can''t hide an update'
);

SELECT pg_temp.as_member(1);

SELECT throws_ok(
  $$select public.report_content('activity_update', 'e0000000-0000-4000-8000-000000000331', 'spam')$$,
  '22023',
  'REPORT_OWN',
  'nobody reports their own update'
);

SELECT pg_temp.as_member(3);

SELECT throws_ok(
  $$select public.moderate_hide_update('e0000000-0000-4000-8000-000000000332', ' ')$$,
  '22023',
  'REASON_REQUIRED',
  'hiding an update needs a reason'
);

SELECT lives_ok(
  $$select public.moderate_hide_update('e0000000-0000-4000-8000-000000000332', 'Spam')$$,
  'a moderator hides an update'
);

SELECT throws_ok(
  $$select public.moderate_hide_update('e0000000-0000-4000-8000-000000000332', 'Spam')$$,
  '22023',
  'UPDATE_ALREADY_HIDDEN',
  'once'
);

SELECT results_eq(
  $$select hidden_reason from public.activity_updates
  where id = 'e0000000-0000-4000-8000-000000000332'$$,
  $$values ('Spam'::text)$$,
  'moderators still read a hidden update'
);

RESET ROLE;

SELECT results_eq(
  $$select status, resolution_note from public.reports
  where target_id = 'e0000000-0000-4000-8000-000000000332'$$,
  $$values ('actioned'::text, 'Spam'::text)$$,
  'hiding it deals with its open reports'
);

SELECT results_eq(
  $$select action, target_type, reason, right(actor_id::text, 1) from private.audit_log
  where target_id = 'e0000000-0000-4000-8000-000000000332'$$,
  $$values ('hide'::text, 'activity_update'::text, 'Spam'::text, '3'::text)$$,
  'and goes to the audit log'
);

SET LOCAL ROLE authenticated;

SELECT pg_temp.as_member(2);

SELECT results_eq(
  $$select body from public.activity_updates where activity_id = 'f0000000-0000-4000-8000-000000000331'$$,
  $$values ('Bring a headlamp!'::text)$$,
  'members don''t read a hidden update'
);

SELECT throws_ok(
  $$select public.report_content('activity_update', 'e0000000-0000-4000-8000-000000000332', 'spam')$$,
  'P0002',
  'REPORT_TARGET_NOT_FOUND',
  'or report one'
);

SELECT pg_temp.as_member(1);

SELECT results_eq(
  $$select hidden_reason from public.activity_updates
  where id = 'e0000000-0000-4000-8000-000000000332'$$,
  $$values ('Spam'::text)$$,
  'its author reads it, and why it was hidden'
);

SELECT pg_temp.as_member(3);

SELECT public.moderate_unhide_update('e0000000-0000-4000-8000-000000000332', 'Otto explained');

SELECT throws_ok(
  $$select public.moderate_unhide_update('e0000000-0000-4000-8000-000000000332', 'Again')$$,
  '22023',
  'UPDATE_NOT_HIDDEN',
  'a moderator unhides an update, once'
);

SELECT pg_temp.as_member(2);

SELECT results_eq(
  $$select count(*)::integer from public.activity_updates
  where activity_id = 'f0000000-0000-4000-8000-000000000331'$$,
  $$values (2)$$,
  'and members read it again'
);

RESET ROLE;

SELECT function_privs_are(
  'public',
  'moderate_hide_update',
  ARRAY['uuid', 'text'],
  'anon',
  ARRAY[]::text[],
  'signed-out visitors can''t hide updates'
);

SELECT *
FROM finish();

ROLLBACK;
