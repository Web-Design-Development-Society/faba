-- Suspending and reinstating a member (MOD-04). Design document sections 9.7, 9.8 and 10.3, and
-- FR-MOD-1. A suspended member's profile status is `suspended`, so is_active_member() is false and
-- Row Level Security denies them every read and write but their own profile. Their upcoming
-- activities are hidden. Reinstating them doesn't unhide those. Both write to the audit log (MOD-05).

-- Moderators read every profile, so they can see who's suspended and reinstate them.
DROP POLICY "Members read their own profile, and active members read active profiles" ON public.profiles;

CREATE POLICY "Members read their own profile, active members read active profiles, and moderators read all" ON public.profiles
FOR SELECT
TO authenticated
USING (
  id = (SELECT auth.uid())
  OR ((SELECT private.is_active_member()) AND status = 'active')
  OR (SELECT private.is_moderator()) IS TRUE
);

-- Suspends an active member, with a reason for the audit log. Only moderators and admins can, not
-- on themselves, and only admins can suspend a moderator or an admin. Their open reports are dealt
-- with, and their activities that aren't over are hidden through moderate_hide(), which logs each.
CREATE FUNCTION public.suspend_member(user_id uuid, reason text)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
declare
  target public.profiles;
  why text := nullif(trim(suspend_member.reason), '');
  actioned integer;
  hidden integer := 0;
  activity_id uuid;
begin
  if not private.is_moderator() then
    raise exception 'NOT_MODERATOR' using errcode = '42501';
  end if;

  if why is null then
    raise exception 'REASON_REQUIRED' using errcode = '22023';
  end if;

  select * into target
  from public.profiles as p
  where p.id = suspend_member.user_id
  for update;

  if not found or target.status = 'ineligible' then
    raise exception 'MEMBER_NOT_FOUND' using errcode = 'P0002';
  end if;

  if target.id = auth.uid() then
    raise exception 'SUSPEND_SELF' using errcode = '22023';
  end if;

  if target.role <> 'member' and not exists (
    select from public.profiles as p where p.id = auth.uid() and p.role = 'admin'
  ) then
    raise exception 'SUSPEND_MODERATOR' using errcode = '42501';
  end if;

  if target.status = 'suspended' then
    raise exception 'ALREADY_SUSPENDED' using errcode = '22023';
  end if;

  update public.profiles as p
  set status = 'suspended'
  where p.id = target.id;

  update public.reports as r
  set status = 'actioned', resolved_by = auth.uid(), resolved_at = now(), resolution_note = why
  where r.target_type = 'profile' and r.target_id = target.id and r.status = 'open';
  get diagnostics actioned = row_count;

  for activity_id in
    select a.id
    from public.activities as a
    where
      a.organizer_id = target.id
      and a.hidden_at is null
      and a.status = 'published'
      and coalesce(a.ends_at, a.starts_at + interval '3 hours') > now()
    order by a.starts_at, a.id
  loop
    perform public.moderate_hide(activity_id, 'Its organizer was suspended.');
    hidden := hidden + 1;
  end loop;

  perform private.audit(
    'suspend',
    'profile',
    target.id,
    why,
    jsonb_build_object('reports_actioned', actioned, 'activities_hidden', hidden)
  );
end;
$$;

-- Reinstates a suspended member, with a reason for the audit log. Only moderators and admins can.
-- Their hidden activities stay hidden, for a moderator to unhide one by one (MOD-03).
CREATE FUNCTION public.reinstate_member(user_id uuid, reason text)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
declare
  target public.profiles;
  why text := nullif(trim(reinstate_member.reason), '');
begin
  if not private.is_moderator() then
    raise exception 'NOT_MODERATOR' using errcode = '42501';
  end if;

  if why is null then
    raise exception 'REASON_REQUIRED' using errcode = '22023';
  end if;

  select * into target
  from public.profiles as p
  where p.id = reinstate_member.user_id
  for update;

  if not found then
    raise exception 'MEMBER_NOT_FOUND' using errcode = 'P0002';
  end if;

  if target.status <> 'suspended' then
    raise exception 'NOT_SUSPENDED' using errcode = '22023';
  end if;

  update public.profiles as p
  set status = 'active'
  where p.id = target.id;

  perform private.audit('reinstate', 'profile', target.id, why);
end;
$$;

GRANT EXECUTE ON FUNCTION public.suspend_member(uuid, text) TO authenticated;

GRANT EXECUTE ON FUNCTION public.reinstate_member(uuid, text) TO authenticated;
