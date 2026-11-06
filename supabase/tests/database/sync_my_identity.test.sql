-- Keeping a member's email in step with Google (AUTH-05). Run with `npm run db:test`.
BEGIN;

CREATE EXTENSION IF NOT EXISTS pgtap WITH SCHEMA extensions;

SELECT plan(13);

-- Gina's address changed after a name change, Lou left BYU-Idaho, Sam is suspended and left too,
-- Pat signs in with a password, Rae is back at BYU-Idaho, and Una's new address isn't verified.
INSERT INTO auth.users
  (id, email, raw_user_meta_data)
SELECT
  ('c0000000-0000-4000-8000-0000000001a' || n)::uuid,
  email,
  jsonb_build_object('full_name', name)
FROM (
  VALUES
    (1, 'gina.oldname@byui.edu', 'Gina'),
    (2, 'lou.leaving@byui.edu', 'Lou'),
    (3, 'sam.suspended@byui.edu', 'Sam'),
    (4, 'pat.password@byui.edu', 'Pat'),
    (5, 'rae.returning@byui.edu', 'Rae'),
    (6, 'una.unverified@byui.edu', 'Una')
) AS v (n, email, name);

-- What Google reported at their last sign-in. Pat has no Google identity.
INSERT INTO auth.identities
  (provider_id, user_id, identity_data, provider, created_at, updated_at)
SELECT
  'google-' || n,
  ('c0000000-0000-4000-8000-0000000001a' || n)::uuid,
  jsonb_build_object('email', email, 'email_verified', verified),
  'google',
  now(),
  now()
FROM (
  VALUES
    (1, 'gina.newname@byui.edu', TRUE),
    (2, 'lou@gmail.com', TRUE),
    (3, 'sam@gmail.com', TRUE),
    (5, 'rae.returning@byui.edu', TRUE),
    (6, 'una.new@byui.edu', FALSE)
) AS v (n, email, verified);

UPDATE public.profiles
SET
  guidelines_version = 1,
  guidelines_accepted_at = now(),
  status = CASE id
    WHEN 'c0000000-0000-4000-8000-0000000001a3' THEN 'suspended'
    WHEN 'c0000000-0000-4000-8000-0000000001a5' THEN 'ineligible'
    ELSE 'active'
  END,
  public_email = CASE id
    WHEN 'c0000000-0000-4000-8000-0000000001a1' THEN 'gina.oldname@byui.edu'
    WHEN 'c0000000-0000-4000-8000-0000000001a2' THEN 'lou.leaving@byui.edu'
  END
WHERE id::text LIKE 'c0000000-0000-4000-8000-0000000001a_';

UPDATE public.profile_private
SET email_visible = TRUE
WHERE user_id IN ('c0000000-0000-4000-8000-0000000001a1', 'c0000000-0000-4000-8000-0000000001a2');

-- Lou organizes a hike.
INSERT INTO public.activities
  (id, organizer_id, category_id, title, starts_at, location_name)
VALUES
  (
    'f0000000-0000-4000-8000-0000000001a2',
    'c0000000-0000-4000-8000-0000000001a2',
    'outdoors',
    'Lou''s hike',
    now() + INTERVAL '1 day',
    'R Mountain'
  );

SET LOCAL ROLE authenticated;

-- A new byui.edu address
SELECT set_config(
  'request.jwt.claims',
  '{"sub": "c0000000-0000-4000-8000-0000000001a1", "email": "gina.oldname@byui.edu"}',
  TRUE
);

SELECT results_eq(
  'select public.sync_my_identity()',
  $$values ('active'::text)$$,
  'a member whose byui.edu address changed stays active'
);

SELECT results_eq(
  $$select pp.email::text, p.public_email from public.profile_private as pp
  join public.profiles as p on p.id = pp.user_id where pp.user_id = auth.uid()$$,
  $$values ('gina.newname@byui.edu'::text, 'gina.newname@byui.edu'::text)$$,
  'with the new address in their private profile, and on their profile since they share it'
);

-- No longer byui.edu
SELECT set_config(
  'request.jwt.claims',
  '{"sub": "c0000000-0000-4000-8000-0000000001a2", "email": "lou.leaving@byui.edu"}',
  TRUE
);

SELECT results_eq(
  'select public.sync_my_identity()',
  $$values ('ineligible'::text)$$,
  'a member whose address is no longer byui.edu becomes ineligible'
);

SELECT results_eq(
  $$select pp.email::text, p.public_email, p.status from public.profile_private as pp
  join public.profiles as p on p.id = pp.user_id where pp.user_id = auth.uid()$$,
  $$values ('lou@gmail.com'::text, null::text, 'ineligible'::text)$$,
  'with their new address kept private, even though they shared the old one'
);

SELECT is_empty('select 1 from public.activities', 'and Row Level Security gives them nothing');

SELECT set_config(
  'request.jwt.claims',
  '{"sub": "c0000000-0000-4000-8000-0000000001a1", "email": "gina.newname@byui.edu"}',
  TRUE
);

SELECT is_empty(
  $$select 1 from public.profiles where id = 'c0000000-0000-4000-8000-0000000001a2'$$,
  'other members no longer see their profile'
);

SELECT results_eq(
  $$select title, hidden_at from public.activities where id = 'f0000000-0000-4000-8000-0000000001a2'$$,
  $$values ('Lou''s hike'::text, null::timestamptz)$$,
  'but still see their upcoming activities'
);

-- Other cases
SELECT set_config(
  'request.jwt.claims',
  '{"sub": "c0000000-0000-4000-8000-0000000001a3", "email": "sam.suspended@byui.edu"}',
  TRUE
);

SELECT results_eq(
  'select public.sync_my_identity()',
  $$values ('suspended'::text)$$,
  'a suspension stays, whatever the address'
);

SELECT set_config(
  'request.jwt.claims',
  '{"sub": "c0000000-0000-4000-8000-0000000001a4", "email": "pat.password@byui.edu"}',
  TRUE
);

SELECT results_eq(
  $$select public.sync_my_identity(), (select email::text from public.profile_private where user_id = auth.uid())$$,
  $$values ('active'::text, 'pat.password@byui.edu'::text)$$,
  'without a Google identity, the account''s own email counts'
);

SELECT set_config(
  'request.jwt.claims',
  '{"sub": "c0000000-0000-4000-8000-0000000001a5", "email": "rae.returning@byui.edu"}',
  TRUE
);

SELECT results_eq(
  'select public.sync_my_identity()',
  $$values ('active'::text)$$,
  'a member who''s byui.edu again is active again'
);

SELECT set_config(
  'request.jwt.claims',
  '{"sub": "c0000000-0000-4000-8000-0000000001a6", "email": "una.unverified@byui.edu"}',
  TRUE
);

SELECT results_eq(
  $$select public.sync_my_identity(), (select email::text from public.profile_private where user_id = auth.uid())$$,
  $$values ('active'::text, 'una.unverified@byui.edu'::text)$$,
  'an address Google hasn''t verified doesn''t count'
);

SELECT set_config(
  'request.jwt.claims',
  '{"sub": "c0000000-0000-4000-8000-0000000001ff", "email": "nobody@byui.edu"}',
  TRUE
);

SELECT throws_ok(
  'select public.sync_my_identity()',
  'P0002',
  'ACCOUNT_NOT_FOUND',
  'an account with no profile has nothing to sync'
);

RESET ROLE;

SELECT function_privs_are(
  'public',
  'sync_my_identity',
  ARRAY[]::text[],
  'anon',
  ARRAY[]::text[],
  'visitors can''t call it'
);

SELECT *
FROM finish();

ROLLBACK;
