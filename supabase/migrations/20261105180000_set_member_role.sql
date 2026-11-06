-- Appointing moderators and admins (MOD-06). Design document sections 9.8 and 10.5. In Phase 1, an
-- admin changes a role in the Supabase dashboard with docs/runbooks/roles.md. Roles are read from
-- the database on every request (is_moderator(), get_session_context()), so a change applies on
-- the member's next request. An admin screen arrives in Phase 3 (MOD-08).

-- Sets a member's role, with a reason for the audit log. It's in the private schema, which the
-- Data API never exposes, and only the database owner can call it, so it runs only in the
-- dashboard. FABA always keeps at least one admin.
CREATE FUNCTION private.set_member_role(user_id uuid, role text, reason text)
RETURNS void
LANGUAGE plpgsql
SET search_path = ''
AS $$
declare
  target public.profiles;
  why text := nullif(trim(set_member_role.reason), '');
begin
  if why is null then
    raise exception 'REASON_REQUIRED' using errcode = '22023';
  end if;

  select * into target
  from public.profiles as p
  where p.id = set_member_role.user_id
  for update;

  if not found then
    raise exception 'MEMBER_NOT_FOUND' using errcode = 'P0002';
  end if;

  if target.role = set_member_role.role then
    raise exception 'ROLE_UNCHANGED' using errcode = '22023';
  end if;

  if target.role = 'admin' and not exists (
    select
    from public.profiles as p
    where p.role = 'admin' and p.status = 'active' and p.id <> target.id
  ) then
    raise exception 'LAST_ADMIN' using errcode = '22023';
  end if;

  -- The role's CHECK constraint allows only member, moderator and admin.
  update public.profiles as p
  set role = set_member_role.role
  where p.id = target.id;

  perform private.audit(
    'set_role',
    'profile',
    target.id,
    why,
    jsonb_build_object('from', target.role, 'to', set_member_role.role)
  );
end;
$$;

REVOKE EXECUTE
ON FUNCTION private.set_member_role(uuid, text, text)
FROM PUBLIC, anon, authenticated, service_role;
