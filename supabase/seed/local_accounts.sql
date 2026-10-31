-- Local sign-in accounts for the five test personas, with their roles. Loaded before
-- sample_data.sql by `supabase start` on a new database, and by `supabase db reset`.
-- Local only: never run it against staging or production, which have no password accounts.

-- Every persona signs in with the password faba-local-dev. Email sign-up is off, so these
-- seeded accounts are the only password users (design document section 11.2).
INSERT INTO auth.users
  (
    instance_id,
    id,
    aud,
    role,
    email,
    encrypted_password,
    email_confirmed_at,
    raw_app_meta_data,
    raw_user_meta_data,
    created_at,
    updated_at,
    confirmation_token,
    recovery_token,
    email_change_token_new,
    email_change,
    email_change_token_current,
    reauthentication_token,
    phone_change,
    phone_change_token
  )
SELECT
  '00000000-0000-0000-0000-000000000000',
  p.id,
  'authenticated',
  'authenticated',
  p.email,
  extensions.crypt('faba-local-dev', extensions.gen_salt('bf')),
  now(),
  '{"provider": "email", "providers": ["email"]}',
  jsonb_build_object('full_name', p.full_name),
  now(),
  now(),
  '',
  '',
  '',
  '',
  '',
  '',
  '',
  ''
FROM (
  VALUES
    ('00000000-0000-4000-8000-000000000001'::uuid, 'member.test@byui.edu', 'Maya Member'),
    ('00000000-0000-4000-8000-000000000002'::uuid, 'organizer.test@byui.edu', 'Oscar Organizer'),
    ('00000000-0000-4000-8000-000000000003'::uuid, 'moderator.test@byui.edu', 'Morgan Moderator'),
    ('00000000-0000-4000-8000-000000000004'::uuid, 'admin.test@byui.edu', 'Ada Admin'),
    ('00000000-0000-4000-8000-000000000005'::uuid, 'suspended.test@byui.edu', 'Sam Suspended')
) AS p (id, email, full_name);

INSERT INTO auth.identities
  (provider_id, user_id, identity_data, provider, last_sign_in_at, created_at, updated_at)
SELECT
  id::text,
  id,
  jsonb_build_object('sub', id::text, 'email', email, 'email_verified', TRUE),
  'email',
  now(),
  now(),
  now()
FROM auth.users
WHERE email LIKE '%.test@byui.edu';

-- One moderator, one admin, and one suspended member. Everyone else is an active member.
UPDATE public.profiles
SET
  role = CASE id
    WHEN '00000000-0000-4000-8000-000000000003' THEN 'moderator'
    WHEN '00000000-0000-4000-8000-000000000004' THEN 'admin'
    ELSE 'member'
  END,
  status = CASE id
    WHEN '00000000-0000-4000-8000-000000000005' THEN 'suspended'
    ELSE 'active'
  END
WHERE
  id IN
    (
      '00000000-0000-4000-8000-000000000001',
      '00000000-0000-4000-8000-000000000002',
      '00000000-0000-4000-8000-000000000003',
      '00000000-0000-4000-8000-000000000004',
      '00000000-0000-4000-8000-000000000005'
    );
