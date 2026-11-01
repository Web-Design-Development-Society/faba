-- Accepting the community guidelines on Welcome, and the session context the middleware reads on
-- every request (PROF-01; Iteration 1 tasks DB-6 and AU-5). Design document sections 9.7, 9.8 and
-- 10.5.

-- The guidelines version members must accept. When the guidelines change materially, raise it in a
-- new migration, along with GUIDELINES_VERSION in src/lib/guidelines.ts, and every member accepts
-- them again on their next visit.
CREATE FUNCTION private.guidelines_version()
RETURNS INTEGER
LANGUAGE sql
IMMUTABLE
SET search_path = ''
AS $$
  SELECT 1;
$$;

GRANT EXECUTE ON FUNCTION private.guidelines_version() TO authenticated;

-- Section 9.8: an active member has also accepted the current guidelines, so until they do, they
-- read nothing but their own profile.
CREATE OR REPLACE FUNCTION private.is_active_member()
RETURNS BOOLEAN
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = ''
AS $$
  SELECT private.is_allowed_email(auth.jwt()->>'email')
  AND EXISTS (
    SELECT
    FROM public.profiles
    WHERE
      id = auth.uid()
      AND status = 'active'
      AND guidelines_version >= private.guidelines_version()
  );
$$;

-- What the middleware needs about the signed-in member, in one call. It runs as the caller, who
-- can always read their own profile.
CREATE FUNCTION public.get_session_context()
RETURNS TABLE (
  status text,
  role text,
  display_name text,
  avatar_url text,
  use_initials BOOLEAN,
  guidelines_ok BOOLEAN
)
LANGUAGE sql
STABLE
SET search_path = ''
AS $$
  SELECT
    status,
    role,
    display_name,
    avatar_url,
    use_initials,
    coalesce(guidelines_version >= private.guidelines_version(), FALSE)
  FROM public.profiles
  WHERE id = auth.uid();
$$;

GRANT EXECUTE ON FUNCTION public.get_session_context() TO authenticated;

-- Welcome's one write: the display name, the photo or initials, and accepting the guidelines.
-- `version` is the version the member read, so a change while Welcome was open is caught.
CREATE FUNCTION public.accept_guidelines(version INTEGER, display_name text, use_initials BOOLEAN)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
begin
  -- Not is_active_member(), which needs the guidelines this accepts.
  if not private.is_allowed_email(auth.jwt() ->> 'email') then
    raise exception 'NOT_ELIGIBLE' using errcode = '42501';
  end if;

  if accept_guidelines.version is distinct from private.guidelines_version() then
    raise exception 'GUIDELINES_CHANGED' using errcode = '22023';
  end if;

  -- The display name's CHECK constraint enforces 2 to 50 characters.
  update public.profiles
  set
    display_name = trim(accept_guidelines.display_name),
    use_initials = coalesce(accept_guidelines.use_initials, false),
    guidelines_version = accept_guidelines.version,
    guidelines_accepted_at = now()
  where id = auth.uid() and status = 'active';

  if not found then
    raise exception 'NOT_ACTIVE' using errcode = '42501';
  end if;
end;
$$;

GRANT EXECUTE ON FUNCTION public.accept_guidelines(INTEGER, text, BOOLEAN) TO authenticated;
