-- Comments on activities, and reporting and hiding them (ACT-12). Run with `npm run db:test`.
BEGIN;

CREATE EXTENSION IF NOT EXISTS pgtap WITH SCHEMA extensions;

SELECT plan(18);

-- Otto organizes a hike. Gwen asks a question under it, and Otto answers. Gwen later reports Otto's
-- answer, and Mo, a moderator, hides it.
INSERT INTO auth.users
  (id, email, raw_user_meta_data)
SELECT
  ('c0000000-0000-4000-8000-00000000034' || n)::uuid,
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
  role = CASE id WHEN 'c0000000-0000-4000-8000-000000000343' THEN 'moderator' ELSE 'member' END
WHERE id::text LIKE 'c0000000-0000-4000-8000-00000000034_';

INSERT INTO public.activities
  (id, organizer_id, category_id, title, starts_at, location_name, hidden_at)
VALUES
  (
    'f0000000-0000-4000-8000-000000000341',
    'c0000000-0000-4000-8000-000000000341',
    'outdoors',
    'Hike',
    now() + INTERVAL '1 day',
    'R Mountain trailhead',
    NULL
  ),
  (
    'f0000000-0000-4000-8000-000000000342',
    'c0000000-0000-4000-8000-000000000341',
    'outdoors',
    'Hidden hike',
    now() + INTERVAL '2 days',
    'R Mountain trailhead',
    now()
  );

INSERT INTO public.activity_comments
  (id, activity_id, author_id, body)
VALUES
  (
    'a0000000-0000-4000-8000-000000000341',
    'f0000000-0000-4000-8000-000000000341',
    'c0000000-0000-4000-8000-000000000342',
    'Is there parking at the trailhead?'
  ),
  (
    'a0000000-0000-4000-8000-000000000342',
    'f0000000-0000-4000-8000-000000000341',
    'c0000000-0000-4000-8000-000000000341',
    'Yes, by the gate.'
  );

CREATE FUNCTION pg_temp.as_member(n INTEGER)
RETURNS void
LANGUAGE sql
AS $$
  SELECT set_config(
    'request.jwt.claims',
    jsonb_build_object(
      'sub',
      'c0000000-0000-4000-8000-00000000034' || n,
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
  $$select public.post_comment('f0000000-0000-4000-8000-000000000341', 'Is it dog friendly?')$$,
  'a member posts a comment'
);

SELECT throws_ok(
  $$select public.post_comment('f0000000-0000-4000-8000-000000000341', '   ')$$,
  '22023',
  'INVALID_COMMENT',
  'a blank comment is refused'
);

SELECT throws_ok(
  $$select public.post_comment('f0000000-0000-4000-8000-000000000342', 'Hello?')$$,
  'P0002',
  'ACTIVITY_NOT_FOUND',
  'nobody comments on a hidden activity'
);

SELECT results_eq(
  $$select count(*) from public.activity_comments
  where activity_id = 'f0000000-0000-4000-8000-000000000341'$$,
  $$values (3::bigint)$$,
  'members read the comments on the activity'
);

SELECT lives_ok(
  $$select public.delete_comment('a0000000-0000-4000-8000-000000000341')$$,
  'a member deletes their own comment'
);

SELECT throws_ok(
  $$select public.delete_comment('a0000000-0000-4000-8000-000000000342')$$,
  '42501',
  'NOT_COMMENT_AUTHOR',
  'a member can''t delete someone else''s comment'
);

SELECT lives_ok(
  $$select public.report_content(
    'comment', 'a0000000-0000-4000-8000-000000000342', 'spam', 'Advertising'
  )$$,
  'a member reports a comment'
);

SELECT throws_ok(
  $$select public.report_content('comment', 'a0000000-0000-4000-8000-000000000342', 'spam')$$,
  '23505',
  'ALREADY_REPORTED',
  'a comment is reported once by each member'
);

SELECT pg_temp.as_member(1);

SELECT throws_ok(
  $$select public.report_content('comment', 'a0000000-0000-4000-8000-000000000342', 'spam')$$,
  '22023',
  'REPORT_OWN',
  'nobody reports their own comment'
);

SELECT pg_temp.as_member(3);

SELECT throws_ok(
  $$select public.moderate_hide_comment('a0000000-0000-4000-8000-000000000342', ' ')$$,
  '22023',
  'REASON_REQUIRED',
  'hiding a comment needs a reason'
);

SELECT lives_ok(
  $$select public.moderate_hide_comment('a0000000-0000-4000-8000-000000000342', 'Spam')$$,
  'a moderator hides a comment'
);

SELECT throws_ok(
  $$select public.moderate_hide_comment('a0000000-0000-4000-8000-000000000342', 'Spam')$$,
  '22023',
  'COMMENT_ALREADY_HIDDEN',
  'a comment is hidden once'
);

SELECT results_eq(
  $$select hidden_reason from public.activity_comments
  where id = 'a0000000-0000-4000-8000-000000000342'$$,
  $$values ('Spam'::text)$$,
  'moderators still read a hidden comment, with its reason'
);

SELECT pg_temp.as_member(2);

SELECT results_eq(
  $$select count(*) from public.activity_comments
  where id = 'a0000000-0000-4000-8000-000000000342'$$,
  $$values (0::bigint)$$,
  'members don''t read a hidden comment'
);

SELECT throws_ok(
  $$select public.moderate_hide_comment('a0000000-0000-4000-8000-000000000341', 'Spam')$$,
  '42501',
  'NOT_MODERATOR',
  'members can''t hide a comment'
);

SELECT pg_temp.as_member(3);

SELECT lives_ok(
  $$select public.moderate_unhide_comment('a0000000-0000-4000-8000-000000000342', 'Fine after all')$$,
  'a moderator unhides a comment'
);

SELECT throws_ok(
  $$select public.moderate_unhide_comment('a0000000-0000-4000-8000-000000000342', 'Fine')$$,
  '22023',
  'COMMENT_NOT_HIDDEN',
  'only a hidden comment can be unhidden'
);

RESET ROLE;

SELECT results_eq(
  $$select status, resolution_note from public.reports
  where target_type = 'comment' and target_id = 'a0000000-0000-4000-8000-000000000342'$$,
  $$values ('actioned'::text, 'Spam'::text)$$,
  'hiding a comment deals with its open reports'
);

SELECT * FROM finish();

ROLLBACK;
