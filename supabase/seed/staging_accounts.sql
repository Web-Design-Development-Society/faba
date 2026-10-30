-- Accounts for the five test personas on staging, so sample_data.sql has organizers. They have no
-- password and no Google identity, so nobody can sign in as them, and they're all plain members.
-- The Seed staging workflow runs this, then sample_data.sql. Existing accounts are left alone.
INSERT INTO auth.users
  (
    instance_id,
    id,
    aud,
    role,
    email,
    encrypted_password,
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
  '',
  '{}',
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
) AS p (id, email, full_name)
ON CONFLICT (id) DO NOTHING;
