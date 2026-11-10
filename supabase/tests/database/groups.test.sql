-- Interest groups (GRP-01). Run with `npm run db:test`.
BEGIN;

CREATE EXTENSION IF NOT EXISTS pgtap WITH SCHEMA extensions;

SELECT plan(18);

-- Gil starts groups, Nan hasn't accepted the guidelines, Mod moderates, and Ott is another member.
INSERT INTO auth.users
  (id, email, raw_user_meta_data)
SELECT
  ('c0000000-0000-4000-8000-00000000042' || n)::uuid,
  name || '@byui.edu',
  jsonb_build_object('full_name', name)
FROM (
  VALUES
    (1, 'gil'),
    (2, 'nan'),
    (3, 'mod'),
    (4, 'ott')
) AS v (n, name);

UPDATE public.profiles
SET
  guidelines_version = 1,
  guidelines_accepted_at = now(),
  role = CASE id
    WHEN 'c0000000-0000-4000-8000-000000000423' THEN 'moderator'
    ELSE 'member'
  END
WHERE
  id::text LIKE 'c0000000-0000-4000-8000-00000000042_'
  AND id != 'c0000000-0000-4000-8000-000000000422';

-- Signs in as Gil (1), Nan (2), Mod (3) or Ott (4).
CREATE FUNCTION pg_temp.sign_in(member text)
RETURNS void
LANGUAGE sql
AS $$
  SELECT set_config(
    'request.jwt.claims',
    json_build_object(
      'sub',
      'c0000000-0000-4000-8000-00000000042' || member,
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
  $$select public.create_group('Trail Runners', 'outdoors')$$,
  '42501',
  'NOT_ACTIVE',
  'a member who hasn''t accepted the guidelines can''t start one'
);

SELECT pg_temp.sign_in('1');

SELECT results_eq(
  $$
    select public.create_group(
      name => '  Trail Runners!  ',
      category_id => 'outdoors',
      description => '  Easy miles on Saturdays.  ',
      idempotency_key => 'a0000000-0000-4000-8000-000000000421'
    )
  $$,
  $$values ('trail-runners')$$,
  'a member starts a group, with an address from its name'
);

SELECT results_eq(
  $$
    select name, description, category_id, kind, join_policy, owner_id
    from public.groups
    where slug = 'trail-runners'
  $$,
  $$values (
    'Trail Runners!',
    'Easy miles on Saturdays.',
    'outdoors',
    'interest',
    'open',
    'c0000000-0000-4000-8000-000000000421'::uuid
  )$$,
  'trimmed, open by default, and theirs'
);

SELECT results_eq(
  $$
    select m.user_id, m.role, m.status
    from public.group_members as m
    join public.groups as g on g.id = m.group_id
    where g.slug = 'trail-runners'
  $$,
  $$values ('c0000000-0000-4000-8000-000000000421'::uuid, 'owner', 'active')$$,
  'the creator is its owner'
);

SELECT results_eq(
  $$
    select public.create_group(
      name => 'Trail Runners',
      category_id => 'outdoors',
      idempotency_key => 'a0000000-0000-4000-8000-000000000421'
    )
  $$,
  $$values ('trail-runners')$$,
  'starting it again with the same key finds the first'
);

SELECT results_eq(
  $$select public.create_group('Trail runners', 'outdoors', join_policy => 'approval')$$,
  $$values ('trail-runners-2')$$,
  'a taken address gets a number'
);

SELECT results_eq(
  $$select public.create_group('🏃 🏃', 'outdoors')$$,
  $$values ('group')$$,
  'a name with no letters or numbers gets a plain address'
);

SELECT throws_ok(
  $$select public.create_group('Book club', 'learning')$$,
  'P0001',
  'GROUP_QUOTA_EXCEEDED',
  'a fourth in 30 days is too many'
);

SELECT pg_temp.sign_in('4');

SELECT throws_ok(
  $$select public.create_group('Hi', 'outdoors')$$,
  '22023',
  'INVALID_GROUP_NAME',
  'a name needs 3 characters'
);

SELECT throws_ok(
  $$select public.create_group(repeat('x', 61), 'outdoors')$$,
  '22023',
  'INVALID_GROUP_NAME',
  'and 60 at most'
);

SELECT throws_ok(
  $$select public.create_group('Book club', 'learning', repeat('x', 1001))$$,
  '22023',
  'INVALID_GROUP_DESCRIPTION',
  'a description is 1,000 characters at most'
);

SELECT throws_ok(
  $$select public.create_group('Book club', 'learning', join_policy => 'invite')$$,
  '22023',
  'INVALID_JOIN_POLICY',
  'the join policy is open or approval'
);

SELECT throws_ok(
  $$select public.create_group('Book club', 'nope')$$,
  '22023',
  'INVALID_CATEGORY',
  'the category is one of those offered'
);

SELECT throws_ok(
  $$insert into public.groups (slug, name, category_id) values ('mine', 'Mine', 'outdoors')$$,
  '42501',
  NULL,
  'members can''t write groups directly'
);

-- Gil's first group is hidden.
RESET ROLE;

UPDATE public.groups
SET hidden_at = now()
WHERE slug = 'trail-runners-2';

SET LOCAL ROLE authenticated;

SELECT results_eq(
  $$select slug from public.groups where owner_id = 'c0000000-0000-4000-8000-000000000421' order by slug$$,
  $$values ('group'), ('trail-runners')$$,
  'other members read groups, but not a hidden one'
);

SELECT is_empty(
  $$select from public.group_members where user_id = 'c0000000-0000-4000-8000-000000000421'$$,
  'or the members of a group they''re not in'
);

SELECT pg_temp.sign_in('3');

SELECT results_eq(
  $$select count(*)::integer from public.groups where owner_id = 'c0000000-0000-4000-8000-000000000421'$$,
  $$values (3)$$,
  'moderators read a hidden one'
);

-- Gil moves to a new account, Ott's, who already belongs to Trail Runners.
RESET ROLE;

INSERT INTO public.group_members
  (group_id, user_id, role)
SELECT
  id,
  'c0000000-0000-4000-8000-000000000424',
  'member'
FROM public.groups
WHERE slug = 'trail-runners';

SELECT private.transfer_account(
  'c0000000-0000-4000-8000-000000000421',
  'c0000000-0000-4000-8000-000000000424',
  'New email address'
);

SELECT results_eq(
  $$
    select g.slug, g.owner_id, m.user_id, m.role
    from public.groups as g
    join public.group_members as m on m.group_id = g.id
    where g.slug in ('trail-runners', 'trail-runners-2', 'group')
    order by g.slug
  $$,
  $$values
    ('group', 'c0000000-0000-4000-8000-000000000424'::uuid, 'c0000000-0000-4000-8000-000000000424'::uuid, 'owner'),
    ('trail-runners', 'c0000000-0000-4000-8000-000000000424'::uuid, 'c0000000-0000-4000-8000-000000000424'::uuid, 'owner'),
    ('trail-runners-2', 'c0000000-0000-4000-8000-000000000424'::uuid, 'c0000000-0000-4000-8000-000000000424'::uuid, 'owner')$$,
  'moving an account moves its groups, keeping the higher role'
);

SELECT *
FROM finish();

ROLLBACK;
