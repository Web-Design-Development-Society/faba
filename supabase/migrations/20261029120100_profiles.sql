-- Profiles: a member's identity as others see it, plus a private table for personal data.
-- Design document section 10.3. Row Level Security is on with no policies yet, so the Data API
-- returns nothing until the policies and RPCs arrive (Iteration 1 tasks DB-2 and DB-6).
CREATE TABLE public.profiles (
  id uuid PRIMARY KEY REFERENCES auth.users (id)
    ON DELETE CASCADE,
  display_name text NOT NULL CHECK (char_length(display_name) BETWEEN 2 AND 50),
  avatar_url text,
  use_initials BOOLEAN NOT NULL DEFAULT FALSE,
  department text CHECK (char_length(department) <= 60),
  bio text CHECK (char_length(bio) <= 280),
  interests text[] NOT NULL DEFAULT '{}',
  public_email text,
  timezone text NOT NULL DEFAULT 'America/Denver',
  role text NOT NULL DEFAULT 'member' CHECK (role IN ('member', 'moderator', 'admin')),
  status text NOT NULL DEFAULT 'active' CHECK (status IN ('active', 'suspended', 'ineligible')),
  guidelines_version INTEGER,
  guidelines_accepted_at timestamptz,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now()
);

-- Visible only to the member and moderators. A separate table because RLS works on rows.
-- There is no based_in column while FABA serves Rexburg only (ADR-017).
CREATE TABLE public.profile_private (
  user_id uuid PRIMARY KEY REFERENCES public.profiles (id)
    ON DELETE CASCADE,
  email extensions.citext NOT NULL UNIQUE,
  email_visible BOOLEAN NOT NULL DEFAULT FALSE,
  faculty_type text CHECK (faculty_type IN ('full_time', 'part_time', 'prefer_not')),
  last_seen_at timestamptz,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now()
);

CREATE TRIGGER profiles_set_updated_at
BEFORE UPDATE ON public.profiles
FOR EACH ROW
EXECUTE FUNCTION private.set_updated_at();

CREATE TRIGGER profile_private_set_updated_at
BEFORE UPDATE ON public.profile_private
FOR EACH ROW
EXECUTE FUNCTION private.set_updated_at();

ALTER TABLE public.profiles ENABLE ROW LEVEL SECURITY;

ALTER TABLE public.profile_private ENABLE ROW LEVEL SECURITY;

-- Creates the profile when Supabase Auth creates a user. The display name comes from Google,
-- falling back to the part of the email before the @.
CREATE FUNCTION private.handle_new_user()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
declare
  name text := left(
    trim(coalesce(
      new.raw_user_meta_data ->> 'full_name',
      new.raw_user_meta_data ->> 'name',
      split_part(new.email, '@', 1)
    )),
    50
  );
begin
  if char_length(name) < 2 then
    name := 'Member';
  end if;

  insert into public.profiles (id, display_name, avatar_url)
  values (
    new.id,
    name,
    coalesce(new.raw_user_meta_data ->> 'avatar_url', new.raw_user_meta_data ->> 'picture')
  );

  insert into public.profile_private (user_id, email)
  values (new.id, new.email);

  return new;
end;
$$;

CREATE TRIGGER on_auth_user_created
AFTER INSERT ON auth.users
FOR EACH ROW
EXECUTE FUNCTION private.handle_new_user();
