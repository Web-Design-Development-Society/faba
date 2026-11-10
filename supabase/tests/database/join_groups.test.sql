-- Joining and leaving groups (GRP-02). Run with `npm run db:test`.
BEGIN;

CREATE EXTENSION IF NOT EXISTS pgtap WITH SCHEMA extensions;

SELECT plan(17);

-- Oona owns an open group and an approval group, Ory organizes the approval one, and Jo and Kit
-- join. Sal is suspended.
INSERT INTO auth.users
  (id, email, raw_user_meta_data)
SELECT
  ('c0000000-0000-4000-8000-00000000043' || n)::uuid,
  name || '@byui.edu',
  jsonb_build_object('full_name', name)
FROM (
  VALUES
    (1, 'oona'),
    (2, 'ory'),
    (3, 'jo'),
    (4, 'kit'),
    (5, 'sal')
) AS v (n, name);

UPDATE public.profiles
SET
  guidelines_version = 1,
  guidelines_accepted_at = now(),
  status = CASE id
    WHEN 'c0000000-0000-4000-8000-000000000435' THEN 'suspended'
    ELSE 'active'
  END
WHERE id::text LIKE 'c0000000-0000-4000-8000-00000000043_';

INSERT INTO public.groups
  (id, slug, name, category_id, join_policy, owner_id, archived_at, hidden_at)
VALUES
  (
    'b0000000-0000-4000-8000-000000000431',
    'runners-431',
    'Runners',
    'outdoors',
    'open',
    'c0000000-0000-4000-8000-000000000431',
    NULL,
    NULL
  ),
  (
    'b0000000-0000-4000-8000-000000000432',
    'quilters-432',
    'Quilters',
    'arts',
    'approval',
    'c0000000-0000-4000-8000-000000000431',
    NULL,
    NULL
  ),
  (
    'b0000000-0000-4000-8000-000000000433',
    'archived-433',
    'Old club',
    'games',
    'open',
    'c0000000-0000-4000-8000-000000000431',
    now(),
    NULL
  ),
  (
    'b0000000-0000-4000-8000-000000000434',
    'hidden-434',
    'Hidden club',
    'games',
    'open',
    'c0000000-0000-4000-8000-000000000431',
    NULL,
    now()
  );

INSERT INTO public.group_members
  (group_id, user_id, role)
VALUES
  ('b0000000-0000-4000-8000-000000000431', 'c0000000-0000-4000-8000-000000000431', 'owner'),
  ('b0000000-0000-4000-8000-000000000432', 'c0000000-0000-4000-8000-000000000431', 'owner'),
  ('b0000000-0000-4000-8000-000000000432', 'c0000000-0000-4000-8000-000000000432', 'organizer'),
  ('b0000000-0000-4000-8000-000000000431', 'c0000000-0000-4000-8000-000000000435', 'member');

-- Signs in as Oona (1), Ory (2), Jo (3) or Kit (4).
CREATE FUNCTION pg_temp.sign_in(member text)
RETURNS void
LANGUAGE sql
AS $$
  SELECT set_config(
    'request.jwt.claims',
    json_build_object(
      'sub',
      'c0000000-0000-4000-8000-00000000043' || member,
      'email',
      member || '@byui.edu'
    )::text,
    TRUE
  );
$$;

GRANT EXECUTE ON FUNCTION pg_temp.sign_in(text) TO authenticated;

SET LOCAL ROLE authenticated;

SELECT pg_temp.sign_in('3');

SELECT results_eq(
  $$select public.member_count(g) from public.groups as g where slug = 'runners-431'$$,
  $$values (1)$$,
  'the count leaves out suspended members'
);

SELECT results_eq(
  $$select public.join_group('b0000000-0000-4000-8000-000000000431')$$,
  $$values ('active')$$,
  'joining an open group takes one tap'
);

SELECT results_eq(
  $$select public.join_group('b0000000-0000-4000-8000-000000000431')$$,
  $$values ('active')$$,
  'and joining again changes nothing'
);

SELECT results_eq(
  $$select public.member_count(g), public.my_membership(g) from public.groups as g where slug = 'runners-431'$$,
  $$values (2, 'active')$$,
  'the count goes up, and it''s theirs'
);

SELECT results_eq(
  $$select public.join_group('b0000000-0000-4000-8000-000000000432')$$,
  $$values ('pending')$$,
  'an approval group takes a request'
);

SELECT results_eq(
  $$select public.member_count(g), public.my_membership(g) from public.groups as g where slug = 'quilters-432'$$,
  $$values (2, 'pending')$$,
  'which doesn''t count until it''s approved'
);

SELECT is_empty(
  $$select from public.group_members where group_id = 'b0000000-0000-4000-8000-000000000432' and user_id != auth.uid()$$,
  'someone waiting can''t read the members yet'
);

SELECT throws_ok(
  $$select public.join_group('b0000000-0000-4000-8000-000000000433')$$,
  '22023',
  'GROUP_ARCHIVED',
  'an archived group takes nobody new'
);

SELECT throws_ok(
  $$select public.join_group('b0000000-0000-4000-8000-000000000434')$$,
  'P0002',
  'GROUP_NOT_FOUND',
  'and a hidden one isn''t there'
);

-- The organizers hear about Jo's request.
SELECT pg_temp.sign_in('2');

SELECT results_eq(
  $$
    select type, group_id, activity_id, payload ->> 'name', payload ->> 'member', actor_id, read_at is null
    from public.notifications
  $$,
  $$values (
    'group_join_request',
    'b0000000-0000-4000-8000-000000000432'::uuid,
    null::uuid,
    'Quilters',
    'jo',
    'c0000000-0000-4000-8000-000000000433'::uuid,
    true
  )$$,
  'a request tells the organizers, unread'
);

SELECT pg_temp.sign_in('1');

SELECT results_eq(
  $$select count(*)::integer from public.notifications where type = 'group_join_request'$$,
  $$values (1)$$,
  'the owner too'
);

SELECT throws_ok(
  $$select public.leave_group('b0000000-0000-4000-8000-000000000431')$$,
  '22023',
  'OWNER_CANNOT_LEAVE',
  'the owner can''t leave'
);

SELECT pg_temp.sign_in('3');

SELECT public.leave_group('b0000000-0000-4000-8000-000000000432');

RESET ROLE;

SELECT is_empty(
  $$select from public.notifications where group_id = 'b0000000-0000-4000-8000-000000000432'$$,
  'withdrawing a request takes it back from the organizers'
);

SET LOCAL ROLE authenticated;

SELECT public.leave_group('b0000000-0000-4000-8000-000000000431');

SELECT results_eq(
  $$select public.member_count(g), public.my_membership(g) from public.groups as g where slug = 'runners-431'$$,
  $$values (1, null::text)$$,
  'a member leaves'
);

SELECT lives_ok(
  $$select public.leave_group('b0000000-0000-4000-8000-000000000431')$$,
  'leaving again changes nothing'
);

SELECT pg_temp.sign_in('4');

SELECT throws_ok(
  $$insert into public.group_members (group_id, user_id) values ('b0000000-0000-4000-8000-000000000431', auth.uid())$$,
  '42501',
  NULL,
  'members can''t join by writing rows'
);

SELECT set_config('request.jwt.claims', '{}', TRUE);

SET LOCAL ROLE anon;

SELECT throws_ok(
  $$select public.join_group('b0000000-0000-4000-8000-000000000431')$$,
  '42501',
  NULL,
  'visitors can''t join'
);

RESET ROLE;

SELECT *
FROM finish();

ROLLBACK;
