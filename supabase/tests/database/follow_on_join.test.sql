-- Joining a group follows it (GRP-02, NOTIF-09). Run with `npm run db:test`.
BEGIN;

CREATE EXTENSION IF NOT EXISTS pgtap WITH SCHEMA extensions;

SELECT plan(11);

-- Oli starts two groups: Follow Climbers, which anyone can join, and Follow Readers, which members
-- ask to join. Jo joins the first, and Pia asks to join the second.
INSERT INTO auth.users
  (id, email, raw_user_meta_data)
SELECT
  ('c0000000-0000-4000-8000-00000000097' || n)::uuid,
  name || '@byui.edu',
  jsonb_build_object('full_name', name)
FROM (
  VALUES
    (1, 'oli'),
    (2, 'jo'),
    (3, 'pia')
) AS v (n, name);

UPDATE public.profiles
SET
  guidelines_version = 1,
  guidelines_accepted_at = now()
WHERE id::text LIKE 'c0000000-0000-4000-8000-00000000097_';

-- Signs in as Oli (1), Jo (2) or Pia (3).
CREATE FUNCTION pg_temp.sign_in(member text)
RETURNS void
LANGUAGE sql
AS $$
  SELECT set_config(
    'request.jwt.claims',
    json_build_object(
      'sub',
      'c0000000-0000-4000-8000-00000000097' || member,
      'email',
      member || '@byui.edu'
    )::text,
    TRUE
  );
$$;

GRANT EXECUTE ON FUNCTION pg_temp.sign_in(text) TO authenticated;

-- The groups someone follows, by name, as the database has it.
CREATE FUNCTION pg_temp.followed(member text)
RETURNS SETOF text
LANGUAGE sql
SECURITY DEFINER
AS $$
  SELECT g.name
  FROM public.follows AS f
  JOIN public.groups AS g ON g.id::text = f.target_id
  WHERE
    f.target_type = 'group'
    AND f.user_id = ('c0000000-0000-4000-8000-00000000097' || member)::uuid
  ORDER BY g.name;
$$;

-- A group's id from its name.
CREATE FUNCTION pg_temp.group_id(name text)
RETURNS uuid
LANGUAGE sql
SECURITY DEFINER
AS $$
  SELECT g.id FROM public.groups AS g WHERE g.name = group_id.name;
$$;

GRANT EXECUTE ON FUNCTION pg_temp.group_id(text) TO authenticated;

SET LOCAL ROLE authenticated;

SELECT pg_temp.sign_in('1');

SELECT public.create_group('Follow Climbers', 'outdoors');

SELECT public.create_group('Follow Readers', 'outdoors', NULL, 'approval');

RESET ROLE;

SELECT results_eq(
  $$select * from pg_temp.followed('1')$$,
  $$values ('Follow Climbers'), ('Follow Readers')$$,
  'starting a group follows it'
);

SET LOCAL ROLE authenticated;

SELECT pg_temp.sign_in('2');

SELECT public.join_group(pg_temp.group_id('Follow Climbers'));

SELECT pg_temp.sign_in('3');

SELECT public.join_group(pg_temp.group_id('Follow Readers'));

RESET ROLE;

SELECT results_eq(
  $$select * from pg_temp.followed('2')$$,
  $$values ('Follow Climbers')$$,
  'joining an open group follows it'
);

SELECT is_empty(
  $$select * from pg_temp.followed('3')$$,
  'asking to join doesn''t follow the group yet'
);

SET LOCAL ROLE authenticated;

SELECT pg_temp.sign_in('1');

SELECT public.approve_group_member(
  pg_temp.group_id('Follow Readers'),
  'c0000000-0000-4000-8000-000000000973'
);

RESET ROLE;

SELECT results_eq(
  $$select * from pg_temp.followed('3')$$,
  $$values ('Follow Readers')$$,
  'being approved follows the group'
);

-- Oli posts in Readers, and Pia hears about it without having tapped Follow.
INSERT INTO public.activities
  (organizer_id, category_id, title, starts_at, location_name, visibility, group_id)
VALUES
  (
    'c0000000-0000-4000-8000-000000000971',
    'outdoors',
    'Book swap',
    now() + INTERVAL '2 days',
    'Library',
    'group',
    pg_temp.group_id('Follow Readers')
  );

SELECT results_eq(
  $$select count(*)::int from public.notifications where recipient_id = 'c0000000-0000-4000-8000-000000000973' and type = 'new_activity'$$,
  $$values (1)$$,
  'a new member hears about the group''s new activities'
);

-- Jo unfollows, and is still a member.
SET LOCAL ROLE authenticated;

SELECT pg_temp.sign_in('2');

SELECT public.set_follow('group', pg_temp.group_id('Follow Climbers')::text, FALSE);

RESET ROLE;

SELECT is_empty($$select * from pg_temp.followed('2')$$, 'a member can still unfollow');

SELECT results_eq(
  $$select m.status from public.group_members as m where m.user_id = 'c0000000-0000-4000-8000-000000000972'$$,
  $$values ('active')$$,
  'unfollowing doesn''t leave the group'
);

-- Jo leaves and joins again, which follows it again.
SET LOCAL ROLE authenticated;

SELECT pg_temp.sign_in('2');

SELECT public.set_follow('group', pg_temp.group_id('Follow Climbers')::text, TRUE);

SELECT public.leave_group(pg_temp.group_id('Follow Climbers'));

RESET ROLE;

SELECT is_empty($$select * from pg_temp.followed('2')$$, 'leaving a group unfollows it');

SET LOCAL ROLE authenticated;

SELECT pg_temp.sign_in('2');

SELECT public.join_group(pg_temp.group_id('Follow Climbers'));

RESET ROLE;

SELECT results_eq(
  $$select * from pg_temp.followed('2')$$,
  $$values ('Follow Climbers')$$,
  'joining again follows it again'
);

-- Oli removes Jo.
SET LOCAL ROLE authenticated;

SELECT pg_temp.sign_in('1');

SELECT public.remove_group_member(
  pg_temp.group_id('Follow Climbers'),
  'c0000000-0000-4000-8000-000000000972'
);

RESET ROLE;

SELECT is_empty($$select * from pg_temp.followed('2')$$, 'being removed unfollows the group');

-- A deleted group leaves no follows behind.
DELETE FROM public.groups AS g
WHERE g.id = pg_temp.group_id('Follow Climbers');

SELECT is_empty(
  $$select f.target_id from public.follows as f where f.user_id = 'c0000000-0000-4000-8000-000000000971' and f.target_type = 'group' and f.target_id not in (select g.id::text from public.groups as g)$$,
  'a deleted group''s follows go with it'
);

SELECT * FROM finish();
ROLLBACK;
