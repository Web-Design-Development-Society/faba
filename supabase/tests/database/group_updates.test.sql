-- Group updates (GRP-04). Run with `npm run db:test`.
BEGIN;

CREATE EXTENSION IF NOT EXISTS pgtap WITH SCHEMA extensions;

SELECT plan(14);

-- Uma owns Hikers, Mia is a member, Pip is waiting to join, Oz isn't in it, and Mod moderates.
INSERT INTO auth.users
  (id, email, raw_user_meta_data)
SELECT
  ('c0000000-0000-4000-8000-00000000045' || n)::uuid,
  name || '@byui.edu',
  jsonb_build_object('full_name', name)
FROM (
  VALUES
    (1, 'uma'),
    (2, 'mia'),
    (3, 'pip'),
    (4, 'oz'),
    (5, 'mod')
) AS v (n, name);

UPDATE public.profiles
SET
  guidelines_version = 1,
  guidelines_accepted_at = now(),
  role = CASE id
    WHEN 'c0000000-0000-4000-8000-000000000455' THEN 'moderator'
    ELSE 'member'
  END
WHERE id::text LIKE 'c0000000-0000-4000-8000-00000000045_';

INSERT INTO public.groups
  (id, slug, name, category_id, owner_id)
VALUES
  (
    'b0000000-0000-4000-8000-000000000451',
    'hikers-451',
    'Hikers',
    'outdoors',
    'c0000000-0000-4000-8000-000000000451'
  );

INSERT INTO public.group_members
  (group_id, user_id, role, status)
VALUES
  (
    'b0000000-0000-4000-8000-000000000451',
    'c0000000-0000-4000-8000-000000000451',
    'owner',
    'active'
  ),
  (
    'b0000000-0000-4000-8000-000000000451',
    'c0000000-0000-4000-8000-000000000452',
    'member',
    'active'
  ),
  (
    'b0000000-0000-4000-8000-000000000451',
    'c0000000-0000-4000-8000-000000000453',
    'member',
    'pending'
  );

-- Signs in as Uma (1), Mia (2), Pip (3), Oz (4) or Mod (5).
CREATE FUNCTION pg_temp.sign_in(member text)
RETURNS void
LANGUAGE sql
AS $$
  SELECT set_config(
    'request.jwt.claims',
    json_build_object(
      'sub',
      'c0000000-0000-4000-8000-00000000045' || member,
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
  $$select public.post_group_update('b0000000-0000-4000-8000-000000000451', 'Hi all')$$,
  '42501',
  'NOT_GROUP_ORGANIZER',
  'a member who doesn''t organize the group can''t post to it'
);

SELECT pg_temp.sign_in('1');

SELECT throws_ok(
  $$select public.post_group_update('b0000000-0000-4000-8000-000000000451', '   ')$$,
  '22023',
  'INVALID_BODY',
  'an update needs words'
);

SELECT throws_ok(
  $$select public.post_group_update('b0000000-0000-4000-8000-000000000451', repeat('x', 501))$$,
  '22023',
  'INVALID_BODY',
  'and 500 characters at most'
);

SELECT lives_ok(
  $$
    select public.post_group_update(
      'b0000000-0000-4000-8000-000000000451',
      '  Trail is muddy, bring boots.  ',
      'a0000000-0000-4000-8000-000000000451'
    )
  $$,
  'the owner posts an update'
);

SELECT results_eq(
  $$
    select public.post_group_update(
      'b0000000-0000-4000-8000-000000000451',
      'Again',
      'a0000000-0000-4000-8000-000000000451'
    ) = (select id from public.activity_updates where body = 'Trail is muddy, bring boots.')
  $$,
  $$values (true)$$,
  'posting it again with the same key returns it'
);

SELECT lives_ok(
  $$select public.post_group_update('b0000000-0000-4000-8000-000000000451', 'Second')$$,
  'a second'
);

SELECT lives_ok(
  $$select public.post_group_update('b0000000-0000-4000-8000-000000000451', 'Third')$$,
  'a third'
);

SELECT throws_ok(
  $$select public.post_group_update('b0000000-0000-4000-8000-000000000451', 'Fourth')$$,
  'P0001',
  'GROUP_UPDATE_QUOTA_EXCEEDED',
  'but not a fourth in 24 hours'
);

SELECT pg_temp.sign_in('2');

SELECT results_eq(
  $$select body from public.activity_updates where group_id = 'b0000000-0000-4000-8000-000000000451' order by created_at, body$$,
  $$values ('Second'), ('Third'), ('Trail is muddy, bring boots.')$$,
  'members read the group''s updates'
);

SELECT results_eq(
  $$
    select count(*)::integer, bool_and(group_id = 'b0000000-0000-4000-8000-000000000451'), bool_and(read_at is null)
    from public.notifications
    where type = 'group_update'
  $$,
  $$values (3, true, true)$$,
  'and get each one in Alerts, unread'
);

SELECT lives_ok(
  $$select public.report_content('activity_update', (select id from public.activity_updates where body = 'Second'), 'spam')$$,
  'and can report one'
);

SELECT pg_temp.sign_in('3');

SELECT is_empty(
  $$select from public.activity_updates where group_id = 'b0000000-0000-4000-8000-000000000451'$$,
  'someone waiting to join doesn''t read them'
);

SELECT pg_temp.sign_in('4');

SELECT is_empty(
  $$select from public.notifications where type = 'group_update'$$,
  'and nobody outside the group hears about them'
);

SELECT pg_temp.sign_in('5');

SELECT lives_ok(
  $$select public.moderate_hide_update((select id from public.activity_updates where body = 'Second'), 'Spam')$$,
  'moderators read and hide one'
);

RESET ROLE;

SELECT *
FROM finish();

ROLLBACK;
