-- Keeping a member's email in step with Google (AUTH-05). Design document sections 9.7 and 10.5,
-- and FR-AUTH-6. FABA keys every account by its Supabase user ID, which Supabase ties to Google's
-- stable subject ID, never by email. So when a member's address changes, they keep their account.
-- The callback calls sync_my_identity() on each sign-in.

-- Copies the signed-in member's verified email into their private profile, and into their public
-- email if they share it (PROF-04). The verified email is the one Google reports and says it
-- verified, or else the account's own. If it's no longer allowed (byui.edu), their profile becomes
-- ineligible: hidden from other members, and denied by Row Level Security. If it's allowed again,
-- they're active again. A suspension stays as it is. Returns their status.
CREATE FUNCTION public.sync_my_identity()
RETURNS text
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
declare
  verified text;
  allowed boolean;
  visible boolean;
  was text;
  next_status text;
  next_public text;
begin
  select coalesce(
    (
      select i.identity_data ->> 'email'
      from auth.identities as i
      where
        i.user_id = auth.uid()
        and i.provider = 'google'
        and i.identity_data ->> 'email_verified' = 'true'
      order by i.updated_at desc nulls last
      limit 1
    ),
    (select u.email from auth.users as u where u.id = auth.uid())
  ) into verified;

  select pp.email_visible, p.status into visible, was
  from public.profiles as p
  join public.profile_private as pp on pp.user_id = p.id
  where p.id = auth.uid();

  if verified is null or was is null then
    raise exception 'ACCOUNT_NOT_FOUND' using errcode = 'P0002';
  end if;

  allowed := private.is_allowed_email(verified);
  next_status := case
    when was = 'active' and not allowed then 'ineligible'
    when was = 'ineligible' and allowed then 'active'
    else was
  end;
  next_public := case when visible and allowed then verified end;

  update public.profile_private as pp
  set email = verified
  where pp.user_id = auth.uid() and pp.email is distinct from verified;

  -- Only when something changes, so a sign-in doesn't touch updated_at.
  update public.profiles as p
  set public_email = next_public, status = next_status
  where
    p.id = auth.uid()
    and (p.public_email is distinct from next_public or p.status <> next_status);

  return next_status;
end;
$$;

GRANT EXECUTE ON FUNCTION public.sync_my_identity() TO authenticated;
