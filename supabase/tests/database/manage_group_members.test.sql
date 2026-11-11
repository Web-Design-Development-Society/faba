-- Managing a group's members and organizers (GRP-05). Run with `npm run db:test`.
BEGIN;

CREATE EXTENSION IF NOT EXISTS pgtap WITH SCHEMA extensions;

SELECT plan(23);

-- Uma owns Hikers, which members ask to join, Ola organizes it, and Mia is a member. Pip and Pat
-- ask to join, and Mod moderates.
INSERT INTO auth.users
  (id, email, raw_user_meta_data)
SELECT
  ('c0000000-0000-4000-8000-00000000046' || n)::uuid,
  name || '@byui.edu',
  jsonb_build_object('full_name', name)
FROM (
  VALUES
    (1, 'uma'),
    (2, 'ola'),
    (3, 'mia'),
    (4, 'pip'),
    (5, 'pat'),
    (6, 'mod')
) AS v (n, name);

UPDATE public.profiles
SET
  guidelines_version = 1,
  guidelines_accepted_at = now(),
  role = CASE id
    WHEN 'c0000000-0000-4000-8000-000000000466' THEN 'moderator'
    ELSE 'member'
  END
WHERE id::text LIKE 'c0000000-0000-4000-8000-00000000046_';

INSERT INTO public.groups
  (id, slug, name, category_id, join_policy, owner_id)
VALUES
  (
    'b0000000-0000-4000-8000-000000000461',
    'hikers-461',
    'Hikers',
    'outdoors',
    'approval',
    'c0000000-0000-4000-8000-000000000461'
  );

INSERT INTO public.group_members
  (group_id, user_id, role)
VALUES
  ('b0000000-0000-4000-8000-000000000461', 'c0000000-0000-4000-8000-000000000461', 'owner'),
  ('b0000000-0000-4000-8000-000000000461', 'c0000000-0000-4000-8000-000000000462', 'organizer'),
  ('b0000000-0000-4000-8000-000000000461', 'c0000000-0000-4000-8000-000000000463', 'member');

-- Signs in as Uma (1), Ola (2), Mia (3), Pip (4), Pat (5) or Mod (6).
CREATE FUNCTION pg_temp.sign_in(member text)
RETURNS void
LANGUAGE sql
AS $$
  SELECT set_config(
    'request.jwt.claims',
    json_build_object(
      'sub',
      'c0000000-0000-4000-8000-00000000046' || member,
      'email',
      member || '@byui.edu'
    )::text,
    TRUE
  );
$$;

GRANT EXECUTE ON FUNCTION pg_temp.sign_in(text) TO authenticated;

-- Whose role in Hikers is what, as the database has it.
CREATE FUNCTION pg_temp.roles()
RETURNS TABLE (member text, role text)
LANGUAGE sql
SECURITY DEFINER
AS $$
  SELECT right(m.user_id::text, 1), m.role
  FROM public.group_members AS m
  WHERE m.group_id = 'b0000000-0000-4000-8000-000000000461'
  ORDER BY 1;
$$;

GRANT EXECUTE ON FUNCTION pg_temp.roles() TO authenticated;

SET LOCAL ROLE authenticated;

SELECT pg_temp.sign_in('4');

SELECT public.join_group('b0000000-0000-4000-8000-000000000461');

SELECT pg_temp.sign_in('5');

SELECT public.join_group('b0000000-0000-4000-8000-000000000461');

SELECT pg_temp.sign_in('3');

SELECT throws_ok(
  $$select public.approve_group_member('b0000000-0000-4000-8000-000000000461', 'c0000000-0000-4000-8000-000000000464')$$,
  '42501',
  'NOT_GROUP_ORGANIZER',
  'a member can''t approve a request'
);

SELECT pg_temp.sign_in('2');

SELECT lives_ok(
  $$select public.approve_group_member('b0000000-0000-4000-8000-000000000461', 'c0000000-0000-4000-8000-000000000464')$$,
  'an organizer approves one'
);

SELECT is_empty(
  $$select from public.notifications where dedupe_key like 'group_join_request:%:c0000000-0000-4000-8000-000000000464'$$,
  'and the request leaves their Alerts'
);

SELECT pg_temp.sign_in('1');

SELECT is_empty(
  $$select from public.notifications where dedupe_key like 'group_join_request:%:c0000000-0000-4000-8000-000000000464'$$,
  'and the owner''s'
);

SELECT pg_temp.sign_in('4');

SELECT results_eq(
  $$
    select m.status, n.type, n.group_id, n.read_at is null
    from public.group_members as m, public.notifications as n
    where m.user_id = auth.uid()
  $$,
  $$values ('active', 'group_join_approved', 'b0000000-0000-4000-8000-000000000461'::uuid, true)$$,
  'the member is in, and hears so in Alerts'
);

SELECT pg_temp.sign_in('2');

SELECT lives_ok(
  $$select public.remove_group_member('b0000000-0000-4000-8000-000000000461', 'c0000000-0000-4000-8000-000000000465')$$,
  'an organizer declines a request'
);

SELECT pg_temp.sign_in('5');

SELECT is_empty(
  $$select from public.group_members union all select from public.notifications$$,
  'quietly'
);

SELECT pg_temp.sign_in('2');

SELECT throws_ok(
  $$select public.set_group_role('b0000000-0000-4000-8000-000000000461', 'c0000000-0000-4000-8000-000000000463', 'organizer')$$,
  '42501',
  'NOT_GROUP_OWNER',
  'an organizer can''t make organizers'
);

SELECT throws_ok(
  $$select public.remove_group_member('b0000000-0000-4000-8000-000000000461', 'c0000000-0000-4000-8000-000000000461')$$,
  '22023',
  'CANNOT_MANAGE_OWNER',
  'or remove the owner'
);

SELECT pg_temp.sign_in('1');

SELECT lives_ok(
  $$select public.set_group_role('b0000000-0000-4000-8000-000000000461', 'c0000000-0000-4000-8000-000000000463', 'organizer')$$,
  'the owner makes a member an organizer'
);

SELECT throws_ok(
  $$select public.set_group_role('b0000000-0000-4000-8000-000000000461', 'c0000000-0000-4000-8000-000000000461', 'member')$$,
  '22023',
  'CANNOT_MANAGE_OWNER',
  'but can''t step down without handing the group on'
);

SELECT pg_temp.sign_in('2');

SELECT throws_ok(
  $$select public.remove_group_member('b0000000-0000-4000-8000-000000000461', 'c0000000-0000-4000-8000-000000000463')$$,
  '42501',
  'NOT_GROUP_OWNER',
  'only the owner removes an organizer'
);

SELECT lives_ok(
  $$select public.remove_group_member('b0000000-0000-4000-8000-000000000461', 'c0000000-0000-4000-8000-000000000464')$$,
  'and an organizer removes a member'
);

SELECT throws_ok(
  $$select public.transfer_group('b0000000-0000-4000-8000-000000000461', 'c0000000-0000-4000-8000-000000000462')$$,
  '42501',
  'NOT_GROUP_OWNER',
  'an organizer can''t hand the group on'
);

SELECT pg_temp.sign_in('1');

SELECT lives_ok(
  $$select public.transfer_group('b0000000-0000-4000-8000-000000000461', 'c0000000-0000-4000-8000-000000000462')$$,
  'the owner hands it on'
);

SELECT results_eq(
  $$select * from pg_temp.roles()$$,
  $$values ('1', 'organizer'), ('2', 'owner'), ('3', 'organizer')$$,
  'staying on as an organizer'
);

SELECT lives_ok(
  $$select public.leave_group('b0000000-0000-4000-8000-000000000461')$$,
  'and then can leave'
);

SELECT pg_temp.sign_in('2');

SELECT results_eq(
  $$
    select g.owner_id, n.type
    from public.groups as g, public.notifications as n
    where g.id = 'b0000000-0000-4000-8000-000000000461' and n.group_id = g.id
  $$,
  $$values ('c0000000-0000-4000-8000-000000000462'::uuid, 'group_owner')$$,
  'the new owner owns it, and hears so'
);

SELECT pg_temp.sign_in('6');

SELECT results_eq(
  $$select count(*)::integer from public.group_members where group_id = 'b0000000-0000-4000-8000-000000000461'$$,
  $$values (2)$$,
  'moderators read its members'
);

SELECT throws_ok(
  $$select public.transfer_group('b0000000-0000-4000-8000-000000000461', 'c0000000-0000-4000-8000-000000000463')$$,
  '22023',
  'REASON_REQUIRED',
  'and hand it on only with a reason'
);

SELECT throws_ok(
  $$select public.transfer_group('b0000000-0000-4000-8000-000000000461', 'c0000000-0000-4000-8000-000000000465', 'Owner asked')$$,
  'P0002',
  'MEMBER_NOT_FOUND',
  'to one of its members'
);

SELECT lives_ok(
  $$select public.transfer_group('b0000000-0000-4000-8000-000000000461', 'c0000000-0000-4000-8000-000000000463', 'Owner asked')$$,
  'a moderator hands it on'
);

RESET ROLE;

SELECT results_eq(
  $$
    select actor_id, reason, metadata ->> 'to'
    from private.audit_log
    where action = 'transfer_group' and target_id = 'b0000000-0000-4000-8000-000000000461'
  $$,
  $$values ('c0000000-0000-4000-8000-000000000466'::uuid, 'Owner asked', 'c0000000-0000-4000-8000-000000000463')$$,
  'and the audit log keeps it'
);

SELECT *
FROM finish();

ROLLBACK;
