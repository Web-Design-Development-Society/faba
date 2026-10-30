-- The byui.edu eligibility gate, and read access for active members (FND-10; Iteration 1 tasks
-- DB-2, DB-5 and DB-7). Design document sections 9.5, 9.7 and 9.8, and ADR-005.

-- Privileges. Signed-out visitors (anon) get nothing. Signed-in users (authenticated) only read
-- tables, because writes will go through functions that check every rule (section 9.5). The
-- default privileges apply the same rules to tables and functions that later migrations create.
REVOKE ALL ON ALL TABLES IN SCHEMA public FROM anon;

REVOKE ALL ON ALL SEQUENCES IN SCHEMA public FROM anon;

REVOKE INSERT, UPDATE, DELETE, TRUNCATE, REFERENCES, TRIGGER
ON ALL TABLES IN SCHEMA public
FROM authenticated;

ALTER DEFAULT PRIVILEGES FOR ROLE postgres IN SCHEMA public REVOKE ALL ON TABLES FROM anon;

ALTER DEFAULT PRIVILEGES FOR ROLE postgres IN SCHEMA public REVOKE ALL ON SEQUENCES FROM anon;

ALTER DEFAULT PRIVILEGES
FOR ROLE postgres
IN SCHEMA public
REVOKE INSERT, UPDATE, DELETE, TRUNCATE, REFERENCES, TRIGGER ON TABLES FROM authenticated;

-- Postgres lets everyone (PUBLIC) run a new function. That default can only be removed for all
-- schemas at once, not per schema. In public, Supabase's own defaults still let signed-in users
-- run the RPC functions to come.
ALTER DEFAULT PRIVILEGES FOR ROLE postgres REVOKE EXECUTE ON FUNCTIONS FROM PUBLIC;

ALTER DEFAULT PRIVILEGES FOR ROLE postgres IN SCHEMA public REVOKE EXECUTE ON FUNCTIONS FROM anon;

-- Helper functions live in the private schema, which the Data API doesn't expose. Nobody can run
-- them unless a grant below says so. Policies call them as the signed-in user, who therefore
-- needs USAGE on the schema.
REVOKE EXECUTE ON ALL FUNCTIONS IN SCHEMA private FROM PUBLIC;

GRANT USAGE ON SCHEMA private TO authenticated, supabase_auth_admin;

-- True when the part after the @ is exactly byui.edu, ignoring case. Subdomains such as
-- student.byui.edu and lookalikes such as byui.edu.evil.com don't match (ADR-005, ADR-015).
CREATE FUNCTION private.is_allowed_email(email text)
RETURNS BOOLEAN
LANGUAGE sql
IMMUTABLE
SET search_path = ''
AS $$
  SELECT coalesce(email ~* '^[^@]+@byui\.edu$', FALSE);
$$;

-- Supabase Auth calls this before it creates any account (the before-user-created hook), so an
-- account that isn't byui.edu is never created. It's switched on in config.toml locally, and in
-- the dashboard for staging and production (docs/runbooks/supabase-settings.md).
CREATE FUNCTION private.before_user_created(event jsonb)
RETURNS jsonb
LANGUAGE plpgsql
SET search_path = ''
AS $$
begin
  if private.is_allowed_email(event -> 'user' ->> 'email') then
    return '{}'::jsonb;
  end if;

  return jsonb_build_object(
    'error', jsonb_build_object(
      'message', 'FABA is for BYU-Idaho. Sign in with your byui.edu account.',
      'http_code', 403
    )
  );
end;
$$;

GRANT EXECUTE ON FUNCTION private.is_allowed_email(text) TO supabase_auth_admin;

GRANT EXECUTE ON FUNCTION private.before_user_created(jsonb) TO supabase_auth_admin;

-- The last layer of the gate (section 9.7): the signed-in user's email is allowed and their
-- profile is active. SECURITY DEFINER lets it read profiles without going through the profiles
-- policy, which calls it. The guidelines check joins it with the Welcome screen (PROF-01).
CREATE FUNCTION private.is_active_member()
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
    WHERE id = auth.uid() AND status = 'active'
  );
$$;

GRANT EXECUTE ON FUNCTION private.is_active_member() TO authenticated;

-- Read policies. One SELECT policy per table, with function calls wrapped in a subquery so
-- Postgres runs them once per statement rather than once per row (section 9.8).
-- `IS TRUE` keeps Prettier from removing the parentheses the subquery needs.
CREATE POLICY "Active members read categories" ON public.categories
FOR SELECT
TO authenticated
USING ((SELECT private.is_active_member()) IS TRUE);

-- Organizers still see their own hidden activities. Moderators get access with the moderation
-- stories.
CREATE POLICY "Active members read activities that aren't hidden" ON public.activities
FOR SELECT
TO authenticated
USING (
  (SELECT private.is_active_member())
  AND (hidden_at IS NULL OR organizer_id = (SELECT auth.uid()))
);

-- Members always read their own profile, even when suspended, so the app can show who's signed
-- in.
CREATE POLICY "Members read their own profile, and active members read active profiles" ON public.profiles
FOR SELECT
TO authenticated
USING (id = (SELECT auth.uid()) OR ((SELECT private.is_active_member()) AND status = 'active'));
