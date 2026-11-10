-- Group activities and who sees them (GRP-03). Run with `npm run db:test`.
BEGIN;

CREATE EXTENSION IF NOT EXISTS pgtap WITH SCHEMA extensions;

SELECT plan(17);

-- Gwen owns Runners and is an admin, Ida is in it, Out isn't, Pen is waiting to join, and Mod
-- moderates.
INSERT INTO auth.users
  (id, email, raw_user_meta_data)
SELECT
  ('c0000000-0000-4000-8000-00000000044' || n)::uuid,
  name || '@byui.edu',
  jsonb_build_object('full_name', name)
FROM (
  VALUES
    (1, 'gwen'),
    (2, 'ida'),
    (3, 'out'),
    (4, 'pen'),
    (5, 'mod')
) AS v (n, name);

UPDATE public.profiles
SET
  guidelines_version = 1,
  guidelines_accepted_at = now(),
  role = CASE id
    WHEN 'c0000000-0000-4000-8000-000000000441' THEN 'admin'
    WHEN 'c0000000-0000-4000-8000-000000000445' THEN 'moderator'
    ELSE 'member'
  END
WHERE id::text LIKE 'c0000000-0000-4000-8000-00000000044_';

INSERT INTO public.groups
  (id, slug, name, category_id, owner_id, archived_at)
VALUES
  (
    'b0000000-0000-4000-8000-000000000441',
    'runners-441',
    'Runners',
    'outdoors',
    'c0000000-0000-4000-8000-000000000441',
    NULL
  ),
  (
    'b0000000-0000-4000-8000-000000000442',
    'old-442',
    'Old club',
    'outdoors',
    'c0000000-0000-4000-8000-000000000441',
    now()
  );

INSERT INTO public.group_members
  (group_id, user_id, role, status)
VALUES
  (
    'b0000000-0000-4000-8000-000000000441',
    'c0000000-0000-4000-8000-000000000441',
    'owner',
    'active'
  ),
  (
    'b0000000-0000-4000-8000-000000000442',
    'c0000000-0000-4000-8000-000000000441',
    'owner',
    'active'
  ),
  (
    'b0000000-0000-4000-8000-000000000441',
    'c0000000-0000-4000-8000-000000000442',
    'member',
    'active'
  ),
  (
    'b0000000-0000-4000-8000-000000000441',
    'c0000000-0000-4000-8000-000000000444',
    'member',
    'pending'
  );

-- Signs in as Gwen (1), Ida (2), Out (3), Pen (4) or Mod (5).
CREATE FUNCTION pg_temp.sign_in(member text)
RETURNS void
LANGUAGE sql
AS $$
  SELECT set_config(
    'request.jwt.claims',
    json_build_object(
      'sub',
      'c0000000-0000-4000-8000-00000000044' || member,
      'email',
      member || '@byui.edu'
    )::text,
    TRUE
  );
$$;

GRANT EXECUTE ON FUNCTION pg_temp.sign_in(text) TO authenticated;

-- Posts as the signed-in member, next week.
CREATE FUNCTION pg_temp.post(
  title text,
  group_id uuid DEFAULT NULL,
  visibility text DEFAULT 'members'
)
RETURNS uuid
LANGUAGE sql
AS $$
  SELECT public.create_activity(
    title => title,
    category_id => 'outdoors',
    starts_at => now() + INTERVAL '7 days',
    location_name => 'Trailhead',
    group_id => group_id,
    visibility => visibility
  );
$$;

GRANT EXECUTE ON FUNCTION pg_temp.post(text, uuid, text) TO authenticated;

SET LOCAL ROLE authenticated;

SELECT pg_temp.sign_in('1');

SELECT lives_ok(
  $$select pg_temp.post('Members run', 'b0000000-0000-4000-8000-000000000441', 'group')$$,
  'an organizer of a group posts an activity for its members'
);

SELECT lives_ok(
  $$select pg_temp.post('Open run', 'b0000000-0000-4000-8000-000000000441')$$,
  'or under the group, for everyone'
);

-- The ids, for trying them as someone outside the group.
RESET ROLE;

CREATE TABLE pg_temp.posted AS
  SELECT
    id,
    title
  FROM public.activities
  WHERE title IN ('Members run', 'Open run');

GRANT SELECT ON pg_temp.posted TO authenticated;

SET LOCAL ROLE authenticated;

SELECT results_eq(
  $$select title, group_id, visibility from public.activities where title in ('Members run', 'Open run') order by title$$,
  $$values
    ('Members run', 'b0000000-0000-4000-8000-000000000441'::uuid, 'group'),
    ('Open run', 'b0000000-0000-4000-8000-000000000441'::uuid, 'members')$$,
  'they keep the group and who sees them'
);

SELECT throws_ok(
  $$select pg_temp.post('Lonely run', null, 'group')$$,
  '22023',
  'INVALID_VISIBILITY',
  'a members-only activity needs a group'
);

SELECT throws_ok(
  $$select pg_temp.post('Odd run', null, 'friends')$$,
  '22023',
  'INVALID_VISIBILITY',
  'and visibility is everyone or the group'
);

SELECT throws_ok(
  $$select pg_temp.post('Old run', 'b0000000-0000-4000-8000-000000000442')$$,
  '42501',
  'NOT_GROUP_ORGANIZER',
  'not under an archived group'
);

SELECT pg_temp.sign_in('2');

SELECT throws_ok(
  $$select pg_temp.post('My run', 'b0000000-0000-4000-8000-000000000441')$$,
  '42501',
  'NOT_GROUP_ORGANIZER',
  'a member who doesn''t organize the group can''t post under it'
);

SELECT results_eq(
  $$select title from public.activities where group_id = 'b0000000-0000-4000-8000-000000000441' order by title$$,
  $$values ('Members run'), ('Open run')$$,
  'members of the group see both'
);

SELECT lives_ok(
  $$select public.rsvp((select id from public.activities where title = 'Members run'), 'going')$$,
  'and can say I''m in'
);

SELECT pg_temp.sign_in('3');

SELECT results_eq(
  $$select title from public.activities where group_id = 'b0000000-0000-4000-8000-000000000441'$$,
  $$values ('Open run')$$,
  'others see only the one for everyone'
);

SELECT throws_ok(
  $$select public.rsvp((select id from pg_temp.posted where title = 'Members run'), 'going')$$,
  'P0002',
  'ACTIVITY_NOT_FOUND',
  'and can''t say I''m in to the other, even with its id'
);

SELECT is_empty(
  $$
    select from public.rsvps as r
    join public.activities as a on a.id = r.activity_id
    where a.title = 'Members run' and r.user_id != auth.uid()
  $$,
  'or see who''s going to it'
);

SELECT is_empty(
  $$select from public.search_activities('Members') as a where a.title = 'Members run'$$,
  'and search doesn''t find it'
);

SELECT pg_temp.sign_in('4');

SELECT results_eq(
  $$select title from public.activities where group_id = 'b0000000-0000-4000-8000-000000000441'$$,
  $$values ('Open run')$$,
  'someone waiting to join doesn''t see it yet'
);

SELECT pg_temp.sign_in('5');

SELECT results_eq(
  $$select count(*)::integer from public.activities where group_id = 'b0000000-0000-4000-8000-000000000441'$$,
  $$values (2)$$,
  'moderators see both'
);

SELECT pg_temp.sign_in('1');

SELECT public.set_board_activity(
  (SELECT id FROM public.activities WHERE title = 'Members run'),
  TRUE
);

SELECT throws_ok(
  $$select public.announce_activity((select id from public.activities where title = 'Members run'))$$,
  '22023',
  'ANNOUNCE_UNAVAILABLE',
  'a members-only activity is never announced to everyone'
);

RESET ROLE;

SELECT throws_ok(
  $$update public.activities set group_id = null where title = 'Members run'$$,
  '23514',
  NULL,
  'a members-only activity always has its group'
);

SELECT *
FROM finish();

ROLLBACK;
