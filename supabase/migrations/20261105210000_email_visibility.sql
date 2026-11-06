-- Showing my email on my profile, or not (PROF-04). Design document sections 9.8, 9.14 and 10.3.
-- The email stays in profile_private, which only its owner reads. When a member turns sharing on,
-- profiles.public_email holds a copy, which every active member can read. It's off by default
-- (profile_private.email_visible). Moderators and admins can always look an email up, for safety
-- follow-up, without reading the rest of the private profile, such as faculty type.

-- Turns sharing on or off for the signed-in member, keeping public_email in step.
CREATE FUNCTION public.set_email_visibility(visible BOOLEAN)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
begin
  if not private.is_active_member() then
    raise exception 'NOT_ACTIVE' using errcode = '42501';
  end if;

  update public.profile_private as pp
  set email_visible = set_email_visibility.visible
  where pp.user_id = auth.uid();

  update public.profiles as p
  set public_email = case
    when set_email_visibility.visible then (
      select pp.email from public.profile_private as pp where pp.user_id = auth.uid()
    )
  end
  where p.id = auth.uid();
end;
$$;

-- A member's email, for a moderator or admin. Null for anyone else, and for a member who doesn't
-- exist.
CREATE FUNCTION public.member_email(member_id uuid)
RETURNS text
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = ''
AS $$
  SELECT pp.email::text
  FROM public.profile_private AS pp
  WHERE pp.user_id = member_id AND private.is_moderator();
$$;

GRANT EXECUTE ON FUNCTION public.set_email_visibility(BOOLEAN) TO authenticated;

GRANT EXECUTE ON FUNCTION public.member_email(uuid) TO authenticated;
