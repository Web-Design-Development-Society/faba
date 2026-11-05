-- Members edit their own profile (PROF-02). Run with `npm run db:test`.
BEGIN;

CREATE EXTENSION IF NOT EXISTS pgtap WITH SCHEMA extensions;

SELECT plan(24);

-- Elle edits, Oscar is another member, Sue is suspended, and Newt hasn't accepted the guidelines.
INSERT INTO auth.users
  (id, email, raw_user_meta_data)
VALUES
  ('c0000000-0000-4000-8000-000000000061', 'elle.edits@byui.edu', '{"full_name": "Elle Edits"}'),
  ('c0000000-0000-4000-8000-000000000062', 'oscar.other@byui.edu', '{"full_name": "Oscar Other"}'),
  (
    'c0000000-0000-4000-8000-000000000063',
    'sue.suspended@byui.edu',
    '{"full_name": "Sue Suspended"}'
  ),
  ('c0000000-0000-4000-8000-000000000064', 'newt.new@byui.edu', '{"full_name": "Newt New"}');

UPDATE public.profiles
SET
  guidelines_version = 1,
  guidelines_accepted_at = now(),
  status = CASE id
    WHEN 'c0000000-0000-4000-8000-000000000063' THEN 'suspended'
    ELSE 'active'
  END
WHERE
  id IN
    (
      'c0000000-0000-4000-8000-000000000061',
      'c0000000-0000-4000-8000-000000000062',
      'c0000000-0000-4000-8000-000000000063'
    );

SET LOCAL ROLE authenticated;

SELECT set_config(
  'request.jwt.claims',
  '{"sub": "c0000000-0000-4000-8000-000000000061", "email": "elle.edits@byui.edu"}',
  TRUE
);

-- What a member can change
SELECT lives_ok(
  $$update public.profiles
  set display_name = 'Elle E.', use_initials = true, department = 'Mathematics',
    bio = 'Hikes on Saturdays.', interests = '{outdoors,games}'
  where id = 'c0000000-0000-4000-8000-000000000061'$$,
  'a member edits their own profile'
);

SELECT results_eq(
  $$select display_name, use_initials, department, bio, interests
  from public.profiles where id = 'c0000000-0000-4000-8000-000000000061'$$,
  $$values ('Elle E.'::text, true, 'Mathematics'::text, 'Hikes on Saturdays.'::text,
    '{outdoors,games}'::text[])$$,
  'and it''s saved'
);

SELECT lives_ok(
  $$update public.profile_private set faculty_type = 'part_time'
  where user_id = 'c0000000-0000-4000-8000-000000000061'$$,
  'a member sets their faculty type'
);

SELECT results_eq(
  $$select faculty_type from public.profile_private
  where user_id = 'c0000000-0000-4000-8000-000000000061'$$,
  $$values ('part_time'::text)$$,
  'and reads it back'
);

-- What they can't
SELECT is_empty(
  $$select from public.profile_private where user_id = 'c0000000-0000-4000-8000-000000000062'$$,
  'members can''t read anyone else''s private profile'
);

SELECT results_eq(
  $$with changed as (
    update public.profiles set bio = 'Hacked' where id = 'c0000000-0000-4000-8000-000000000062'
    returning 1
  ) select count(*)::integer from changed$$,
  ARRAY[0],
  'members can''t edit anyone else''s profile'
);

SELECT results_eq(
  $$with changed as (
    update public.profile_private set faculty_type = 'full_time'
    where user_id = 'c0000000-0000-4000-8000-000000000062'
    returning 1
  ) select count(*)::integer from changed$$,
  ARRAY[0],
  'or anyone else''s faculty type'
);

SELECT throws_ok(
  $$update public.profiles set role = 'admin' where id = 'c0000000-0000-4000-8000-000000000061'$$,
  '42501',
  NULL,
  'members can''t change their own role'
);

SELECT throws_ok(
  $$update public.profiles set status = 'active' where id = 'c0000000-0000-4000-8000-000000000061'$$,
  '42501',
  NULL,
  'or status'
);

SELECT throws_ok(
  $$update public.profiles set guidelines_version = 99
  where id = 'c0000000-0000-4000-8000-000000000061'$$,
  '42501',
  NULL,
  'or the guidelines they accepted'
);

SELECT throws_ok(
  $$update public.profiles set avatar_url = 'https://example.com/me.png'
  where id = 'c0000000-0000-4000-8000-000000000061'$$,
  '42501',
  NULL,
  'or their photo, which comes from Google'
);

SELECT throws_ok(
  $$update public.profiles set public_email = 'elle@example.com'
  where id = 'c0000000-0000-4000-8000-000000000061'$$,
  '42501',
  NULL,
  'or the email others see'
);

SELECT throws_ok(
  $$update public.profile_private set email = 'elle@example.com'
  where user_id = 'c0000000-0000-4000-8000-000000000061'$$,
  '42501',
  NULL,
  'or their email'
);

SELECT throws_ok(
  $$update public.profile_private set email_visible = true
  where user_id = 'c0000000-0000-4000-8000-000000000061'$$,
  '42501',
  NULL,
  'or whether it''s shown, until PROF-04'
);

-- The limits
SELECT throws_ok(
  $$update public.profiles set display_name = 'E' where id = 'c0000000-0000-4000-8000-000000000061'$$,
  '23514',
  NULL,
  'a display name has 2 characters at least'
);

SELECT throws_ok(
  $$update public.profiles set department = repeat('a', 61)
  where id = 'c0000000-0000-4000-8000-000000000061'$$,
  '23514',
  NULL,
  'a department has 60 at most'
);

SELECT throws_ok(
  $$update public.profiles set bio = repeat('a', 281)
  where id = 'c0000000-0000-4000-8000-000000000061'$$,
  '23514',
  NULL,
  'a bio has 280 at most'
);

SELECT throws_ok(
  $$update public.profiles set interests = array_fill('games'::text, ARRAY[21])
  where id = 'c0000000-0000-4000-8000-000000000061'$$,
  '23514',
  NULL,
  'and interests 20 at most'
);

-- Members who aren't active
SELECT set_config(
  'request.jwt.claims',
  '{"sub": "c0000000-0000-4000-8000-000000000063", "email": "sue.suspended@byui.edu"}',
  TRUE
);

SELECT results_eq(
  $$with changed as (
    update public.profiles set bio = 'Back again' where id = 'c0000000-0000-4000-8000-000000000063'
    returning 1
  ) select count(*)::integer from changed$$,
  ARRAY[0],
  'a suspended member can''t edit their profile'
);

SELECT results_eq(
  $$with changed as (
    update public.profile_private set faculty_type = 'full_time'
    where user_id = 'c0000000-0000-4000-8000-000000000063'
    returning 1
  ) select count(*)::integer from changed$$,
  ARRAY[0],
  'or their faculty type'
);

SELECT results_eq(
  $$select count(*)::integer from public.profile_private
  where user_id = 'c0000000-0000-4000-8000-000000000063'$$,
  ARRAY[1],
  'but still reads their own private profile'
);

SELECT set_config(
  'request.jwt.claims',
  '{"sub": "c0000000-0000-4000-8000-000000000064", "email": "newt.new@byui.edu"}',
  TRUE
);

SELECT results_eq(
  $$with changed as (
    update public.profiles set bio = 'Hello' where id = 'c0000000-0000-4000-8000-000000000064'
    returning 1
  ) select count(*)::integer from changed$$,
  ARRAY[0],
  'members who haven''t accepted the guidelines edit them on Welcome instead'
);

RESET role;

SELECT ok(
  NOT has_column_privilege('anon', 'public.profiles', 'display_name', 'UPDATE'),
  'signed-out visitors can''t edit profiles'
);

SELECT ok(
  has_column_privilege('authenticated', 'public.profiles', 'bio', 'UPDATE')
  AND has_column_privilege('authenticated', 'public.profile_private', 'faculty_type', 'UPDATE')
  AND NOT has_column_privilege('authenticated', 'public.profiles', 'role', 'UPDATE')
  AND NOT has_column_privilege('authenticated', 'public.profile_private', 'email', 'UPDATE'),
  'signed-in members may update only the granted columns'
);

SELECT *
FROM finish();

ROLLBACK;
