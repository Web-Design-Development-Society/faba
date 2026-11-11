-- Managing a group's members and organizers (GRP-05). Design document sections 7.3, 8.7 and 10.3,
-- and FR-GRP-2. A group's organizers approve or decline requests to join and remove members. Its
-- owner also makes members organizers and back, and hands the group on to another member, who
-- becomes its owner while they stay on as an organizer. The owner still can't leave until they've
-- handed it on (GRP-02). A moderator can hand on any group, such as one whose owner left FABA, and
-- the audit log keeps it.

-- Moderators read every group's members, to choose its next owner.
DROP POLICY "Members read their own memberships and their groups' members" ON public.group_members;

CREATE POLICY "Members read their own memberships and their groups' members" ON public.group_members
FOR SELECT
TO authenticated
USING (
  user_id = (SELECT auth.uid())
  OR (private.is_active_member() AND private.is_group_member(group_id))
  OR private.is_moderator()
);

-- Approved members hear they're in, and a new owner hears the group is theirs.
ALTER TABLE public.notifications
DROP CONSTRAINT notifications_type_check;

ALTER TABLE public.notifications
ADD CONSTRAINT notifications_type_check
  CHECK (
    type IN (
      'activity_changed',
      'activity_cancelled',
      'activity_restored',
      'organizer_update',
      'rsvp_confirmed',
      'new_attendees',
      'reminder',
      'board_announcement',
      'group_join_request',
      'group_update',
      'group_join_approved',
      'group_owner'
    )
  );

-- A moderator handing on a group is audited (section 10.3).
ALTER TABLE private.audit_log
DROP CONSTRAINT audit_log_action_check;

ALTER TABLE private.audit_log
ADD CONSTRAINT audit_log_action_check
  CHECK (
    action IN (
      'hide',
      'unhide',
      'suspend',
      'reinstate',
      'dismiss_report',
      'set_role',
      'delete_account',
      'data_fix',
      'transfer_activity',
      'cancel_activity',
      'set_board_activity',
      'announce_activity',
      'transfer_group'
    )
  );

ALTER TABLE private.audit_log
DROP CONSTRAINT audit_log_target_type_check;

ALTER TABLE private.audit_log
ADD CONSTRAINT audit_log_target_type_check
  CHECK (target_type IN ('activity', 'profile', 'report', 'activity_update', 'group'));

-- Locks and returns group `group_id` for the signed-in member to manage, with their role in it:
-- `owner`, `organizer`, `member`, or null. A hidden group, or one that doesn't exist, is the same,
-- except to moderators.
CREATE FUNCTION private.managed_group(group_id uuid, OUT g public.groups, OUT role text)
LANGUAGE plpgsql
SET search_path = ''
AS $$
begin
  if not private.is_active_member() then
    raise exception 'NOT_ACTIVE' using errcode = '42501';
  end if;

  select * into g from public.groups as x where x.id = managed_group.group_id for update;

  if not found or (g.hidden_at is not null and not private.is_moderator()) then
    raise exception 'GROUP_NOT_FOUND' using errcode = 'P0002';
  end if;

  select m.role into role
  from public.group_members as m
  where m.group_id = g.id and m.user_id = auth.uid() and m.status = 'active';
end;
$$;

REVOKE EXECUTE
ON FUNCTION private.managed_group(uuid)
FROM PUBLIC, anon, authenticated, service_role;

-- Tells `user_id` something about group `g`, keeping the group's id with it.
CREATE FUNCTION private.notify_about_group(user_id uuid, type text, g public.groups)
RETURNS void
LANGUAGE plpgsql
SET search_path = ''
AS $$
declare
  dedupe text := type || ':' || g.id || ':' || user_id;
begin
  perform private.notify(array[user_id], type, null, jsonb_build_object('name', g.name), dedupe);

  update public.notifications as n
  set group_id = g.id
  where n.dedupe_key = dedupe;
end;
$$;

REVOKE EXECUTE
ON FUNCTION private.notify_about_group(uuid, text, public.groups)
FROM PUBLIC, anon, authenticated, service_role;

-- Approves `user_id`'s request to join group `group_id`. Its owner or an organizer can, while the
-- group isn't archived. The request leaves the other organizers' Alerts, and the member hears
-- they're in. Approving someone already in changes nothing.
CREATE FUNCTION public.approve_group_member(group_id uuid, user_id uuid)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
declare
  managed record := private.managed_group(approve_group_member.group_id);
  was text;
begin
  if managed.role is null or managed.role not in ('owner', 'organizer') then
    raise exception 'NOT_GROUP_ORGANIZER' using errcode = '42501';
  end if;

  if (managed.g).archived_at is not null then
    raise exception 'GROUP_ARCHIVED' using errcode = '22023';
  end if;

  select m.status into was
  from public.group_members as m
  where m.group_id = (managed.g).id and m.user_id = approve_group_member.user_id;

  if not found then
    raise exception 'MEMBER_NOT_FOUND' using errcode = 'P0002';
  end if;

  if was = 'active' then
    return;
  end if;

  update public.group_members as m
  set status = 'active', joined_at = now()
  where m.group_id = (managed.g).id and m.user_id = approve_group_member.user_id;

  delete from public.notifications as n
  where n.dedupe_key = 'group_join_request:' || (managed.g).id || ':' || approve_group_member.user_id;

  perform private.notify_about_group(approve_group_member.user_id, 'group_join_approved', managed.g);
end;
$$;

GRANT EXECUTE ON FUNCTION public.approve_group_member(uuid, uuid) TO authenticated;

-- Removes `user_id` from group `group_id`, or declines their request to join, quietly. Its owner or
-- an organizer can remove members, and only its owner can remove an organizer. Nobody removes the
-- owner. Removing someone who isn't in it changes nothing.
CREATE FUNCTION public.remove_group_member(group_id uuid, user_id uuid)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
declare
  managed record := private.managed_group(remove_group_member.group_id);
  was public.group_members;
begin
  if managed.role is null or managed.role not in ('owner', 'organizer') then
    raise exception 'NOT_GROUP_ORGANIZER' using errcode = '42501';
  end if;

  select * into was
  from public.group_members as m
  where m.group_id = (managed.g).id and m.user_id = remove_group_member.user_id;

  if not found then
    return;
  end if;

  if was.role = 'owner' then
    raise exception 'CANNOT_MANAGE_OWNER' using errcode = '22023';
  end if;

  if was.role = 'organizer' and managed.role <> 'owner' then
    raise exception 'NOT_GROUP_OWNER' using errcode = '42501';
  end if;

  delete from public.group_members as m
  where m.group_id = (managed.g).id and m.user_id = remove_group_member.user_id;

  if was.status = 'pending' then
    delete from public.notifications as n
    where n.dedupe_key = 'group_join_request:' || (managed.g).id || ':' || remove_group_member.user_id;
  end if;
end;
$$;

GRANT EXECUTE ON FUNCTION public.remove_group_member(uuid, uuid) TO authenticated;

-- Makes active member `user_id` of group `group_id` an `organizer`, or a `member` again. Only its
-- owner can, and not to themselves: they hand the group on first.
CREATE FUNCTION public.set_group_role(group_id uuid, user_id uuid, role text)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
declare
  managed record := private.managed_group(set_group_role.group_id);
  was public.group_members;
begin
  if set_group_role.role is null or set_group_role.role not in ('organizer', 'member') then
    raise exception 'INVALID_GROUP_ROLE' using errcode = '22023';
  end if;

  if managed.role is distinct from 'owner' then
    raise exception 'NOT_GROUP_OWNER' using errcode = '42501';
  end if;

  select * into was
  from public.group_members as m
  where
    m.group_id = (managed.g).id
    and m.user_id = set_group_role.user_id
    and m.status = 'active';

  if not found then
    raise exception 'MEMBER_NOT_FOUND' using errcode = 'P0002';
  end if;

  if was.role = 'owner' then
    raise exception 'CANNOT_MANAGE_OWNER' using errcode = '22023';
  end if;

  update public.group_members as m
  set role = set_group_role.role
  where m.group_id = (managed.g).id and m.user_id = set_group_role.user_id;
end;
$$;

GRANT EXECUTE ON FUNCTION public.set_group_role(uuid, uuid, text) TO authenticated;

-- Hands group `group_id` on to `user_id`, an active member of it, who becomes its owner and hears
-- about it. The owner who hands it on stays as an organizer. Its owner can, and so can a moderator,
-- with a reason, which the audit log keeps. Handing it to its owner changes nothing.
CREATE FUNCTION public.transfer_group(group_id uuid, user_id uuid, reason text DEFAULT NULL)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
declare
  managed record := private.managed_group(transfer_group.group_id);
  moderating boolean := managed.role is distinct from 'owner';
  was public.group_members;
begin
  if moderating and not private.is_moderator() then
    raise exception 'NOT_GROUP_OWNER' using errcode = '42501';
  end if;

  if moderating and nullif(trim(transfer_group.reason), '') is null then
    raise exception 'REASON_REQUIRED' using errcode = '22023';
  end if;

  select m.* into was
  from public.group_members as m
  join public.profiles as p on p.id = m.user_id
  where
    m.group_id = (managed.g).id
    and m.user_id = transfer_group.user_id
    and m.status = 'active'
    and p.status = 'active';

  if not found then
    raise exception 'MEMBER_NOT_FOUND' using errcode = 'P0002';
  end if;

  if was.role = 'owner' then
    return;
  end if;

  update public.group_members as m
  set role = 'organizer'
  where m.group_id = (managed.g).id and m.role = 'owner';

  update public.group_members as m
  set role = 'owner'
  where m.group_id = (managed.g).id and m.user_id = transfer_group.user_id;

  -- The key belonged to its first owner's request to start it.
  update public.groups as x
  set owner_id = transfer_group.user_id, idempotency_key = null
  where x.id = (managed.g).id;

  if moderating then
    perform private.audit(
      'transfer_group',
      'group',
      (managed.g).id,
      transfer_group.reason,
      jsonb_build_object('from', (managed.g).owner_id, 'to', transfer_group.user_id)
    );
  end if;

  perform private.notify_about_group(transfer_group.user_id, 'group_owner', managed.g);
end;
$$;

GRANT EXECUTE ON FUNCTION public.transfer_group(uuid, uuid, text) TO authenticated;
