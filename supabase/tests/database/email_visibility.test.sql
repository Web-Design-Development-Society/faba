-- Showing my email on my profile, or not (PROF-04). Run with `npm run db:test`.
BEGIN;

CREATE EXTENSION IF NOT EXISTS pgtap WITH SCHEMA extensions;

SELECT plan(13);

-- Elle chooses, Gwen looks, Mo moderates, and Sue is suspended.
INSERT INTO auth.users
  (id, email, raw_user_meta_data)
VALUES
  ('c0000000-0000-4000-8000-0000000000f1', 'elle.email@byui.edu', '{"full_name": "Elle Email"}'),
  ('c0000000-0000-4000-8000-0000000000f2', 'gwen.going@byui.edu', '{"full_name": "Gwen Going"}'),
  (
    'c0000000-0000-4000-8000-0000000000f3',
    'mo.moderator@byui.edu',
    '{"full_name": "Mo Moderator"}'
  ),
  (
    'c0000000-0000-4000-8000-0000000000f4',
    'sue.suspended@byui.edu',
    '{"full_name": "Sue Suspended"}'
  );

UPDATE public.profiles
SET
  guidelines_version = 1,
  guidelines_accepted_at = now(),
  role = CASE id
    WHEN 'c0000000-0000-4000-8000-0000000000f3' THEN 'moderator'
    ELSE 'member'
  END,
  status = CASE id
    WHEN 'c0000000-0000-4000-8000-0000000000f4' THEN 'suspended'
    ELSE 'active'
  END
WHERE id::text LIKE 'c0000000-0000-4000-8000-0000000000f_';

SET LOCAL ROLE authenticated;

SELECT set_config(
  'request.jwt.claims',
  '{"sub": "c0000000-0000-4000-8000-0000000000f1", "email": "elle.email@byui.edu"}',
  TRUE
);

SELECT results_eq(
  'select email_visible from public.profile_private where user_id = auth.uid()',
  $$values (false)$$,
  'sharing my email is off to begin with'
);

SELECT lives_ok('select public.set_email_visibility(true)', 'a member turns it on');

SELECT results_eq(
  $$select p.public_email, pp.email_visible from public.profiles as p
  join public.profile_private as pp on pp.user_id = p.id where p.id = auth.uid()$$,
  $$values ('elle.email@byui.edu'::text, true)$$,
  'and their profile has their email'
);

SELECT set_config(
  'request.jwt.claims',
  '{"sub": "c0000000-0000-4000-8000-0000000000f2", "email": "gwen.going@byui.edu"}',
  TRUE
);

SELECT results_eq(
  $$select public_email from public.profiles where id = 'c0000000-0000-4000-8000-0000000000f1'$$,
  $$values ('elle.email@byui.edu'::text)$$,
  'which other members read'
);

SELECT extensions.is(
  public.member_email('c0000000-0000-4000-8000-0000000000f1'),
  NULL,
  'members can''t look up an email'
);

SELECT set_config(
  'request.jwt.claims',
  '{"sub": "c0000000-0000-4000-8000-0000000000f1", "email": "elle.email@byui.edu"}',
  TRUE
);

SELECT lives_ok('select public.set_email_visibility(false)', 'a member turns it off');

SELECT results_eq(
  $$select p.public_email, pp.email_visible from public.profiles as p
  join public.profile_private as pp on pp.user_id = p.id where p.id = auth.uid()$$,
  $$values (null::text, false)$$,
  'and their email leaves their profile'
);

-- Moderators
SELECT set_config(
  'request.jwt.claims',
  '{"sub": "c0000000-0000-4000-8000-0000000000f3", "email": "mo.moderator@byui.edu"}',
  TRUE
);

SELECT extensions.is(
  public.member_email('c0000000-0000-4000-8000-0000000000f1'),
  'elle.email@byui.edu',
  'a moderator looks up an email that isn''t shared'
);

SELECT extensions.is(
  public.member_email('c0000000-0000-4000-8000-0000000000f4'),
  'sue.suspended@byui.edu',
  'including a suspended member''s'
);

SELECT is_empty(
  $$select 1 from public.profile_private where user_id = 'c0000000-0000-4000-8000-0000000000f1'$$,
  'without reading the rest of their private profile'
);

-- Who can't
SELECT set_config(
  'request.jwt.claims',
  '{"sub": "c0000000-0000-4000-8000-0000000000f4", "email": "sue.suspended@byui.edu"}',
  TRUE
);

SELECT throws_ok(
  'select public.set_email_visibility(true)',
  '42501',
  'NOT_ACTIVE',
  'a suspended member can''t share their email'
);

SELECT throws_ok(
  $$update public.profiles set public_email = 'fake@example.com' where id = auth.uid()$$,
  '42501',
  NULL,
  'nor set their public email directly'
);

RESET ROLE;

SELECT function_privs_are(
  'public',
  'member_email',
  ARRAY['uuid'],
  'anon',
  ARRAY[]::text[],
  'visitors can''t look up emails'
);

SELECT *
FROM finish();

ROLLBACK;
