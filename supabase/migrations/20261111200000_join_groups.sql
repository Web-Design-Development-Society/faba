-- Joining and leaving groups (GRP-02). Design document sections 8.7, 8.8 and 10.3, and FR-GRP-2.
-- Join is one tap for an open group. For an approval group it's a request, which tells the group's
-- organizers, and the member waits as pending until one approves them (GRP-05). Leave is always
-- there, except for the owner, who hands the group on first (GRP-05). Each group shows how many
-- members it has.

-- How many active members `g` has, for its card and page. A field members can select as
-- member_count. It counts rows rather than keeping a total, so it can't drift (ADR-008), and it
-- reads them as its owner, since members can't read the members of a group they're not in.
CREATE FUNCTION public.member_count(g public.groups)
RETURNS INTEGER
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = ''
AS $$
  SELECT count(*)::INTEGER
  FROM public.group_members AS m
  JOIN public.profiles AS p ON p.id = m.user_id
  WHERE m.group_id = g.id AND m.status = 'active' AND p.status = 'active';
$$;

GRANT EXECUTE ON FUNCTION public.member_count(public.groups) TO authenticated;

-- The signed-in member's membership of `g`, `active` or `pending`, or null, as my_membership.
CREATE FUNCTION public.my_membership(g public.groups)
RETURNS text
LANGUAGE sql
STABLE
SET search_path = ''
AS $$
  SELECT m.status
  FROM public.group_members AS m
  WHERE m.group_id = g.id AND m.user_id = auth.uid();
$$;

GRANT EXECUTE ON FUNCTION public.my_membership(public.groups) TO authenticated;

-- Join requests are about a group, not an activity (section 8.8). A notification keeps its group's
-- id, and stays, opening "no longer available", when the group goes.
ALTER TABLE public.notifications
ADD COLUMN group_id uuid REFERENCES public.groups (id)
  ON DELETE SET NULL;

CREATE INDEX notifications_group_idx ON public.notifications (group_id);

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
      'group_join_request'
    )
  );

-- Locks and returns group `group_id` for the signed-in member to join or leave. A hidden one, or one
-- that doesn't exist, is the same, so nobody learns which exist.
CREATE FUNCTION private.joinable_group(group_id uuid)
RETURNS public.groups
LANGUAGE plpgsql
SET search_path = ''
AS $$
declare
  g public.groups;
begin
  if not private.is_active_member() then
    raise exception 'NOT_ACTIVE' using errcode = '42501';
  end if;

  select * into g from public.groups as x where x.id = joinable_group.group_id for update;

  if not found or g.hidden_at is not null then
    raise exception 'GROUP_NOT_FOUND' using errcode = 'P0002';
  end if;

  return g;
end;
$$;

REVOKE EXECUTE
ON FUNCTION private.joinable_group(uuid)
FROM PUBLIC, anon, authenticated, service_role;

-- Joins group `group_id`, or asks to join an approval group, which tells its organizers. Returns the
-- membership: `active` or `pending`. Joining again changes nothing.
CREATE FUNCTION public.join_group(group_id uuid)
RETURNS text
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
declare
  g public.groups := private.joinable_group(join_group.group_id);
  already text;
  request text := 'group_join_request:' || join_group.group_id || ':' || auth.uid();
begin
  select m.status into already
  from public.group_members as m
  where m.group_id = g.id and m.user_id = auth.uid();

  if found then
    return already;
  end if;

  if g.archived_at is not null then
    raise exception 'GROUP_ARCHIVED' using errcode = '22023';
  end if;

  if g.join_policy = 'open' then
    insert into public.group_members (group_id, user_id) values (g.id, auth.uid());
    return 'active';
  end if;

  insert into public.group_members (group_id, user_id, status)
  values (g.id, auth.uid(), 'pending');

  perform private.notify(
    array(
      select m.user_id
      from public.group_members as m
      join public.profiles as p on p.id = m.user_id
      where
        m.group_id = g.id
        and m.role in ('owner', 'organizer')
        and m.status = 'active'
        and p.status = 'active'
    ),
    'group_join_request',
    null,
    jsonb_build_object(
      'name', g.name,
      'member', (select p.display_name from public.profiles as p where p.id = auth.uid())
    ),
    request
  );

  update public.notifications as n
  set group_id = g.id
  where n.dedupe_key = request;

  return 'pending';
end;
$$;

GRANT EXECUTE ON FUNCTION public.join_group(uuid) TO authenticated;

-- Leaves group `group_id`, or withdraws a request to join, which takes it back from the organizers'
-- Alerts. The owner can't leave until they hand the group on (GRP-05). Leaving a group they're not
-- in changes nothing.
CREATE FUNCTION public.leave_group(group_id uuid)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
declare
  g public.groups := private.joinable_group(leave_group.group_id);
  was public.group_members;
begin
  select * into was
  from public.group_members as m
  where m.group_id = g.id and m.user_id = auth.uid();

  if not found then
    return;
  end if;

  if was.role = 'owner' then
    raise exception 'OWNER_CANNOT_LEAVE' using errcode = '22023';
  end if;

  delete from public.group_members as m
  where m.group_id = g.id and m.user_id = auth.uid();

  if was.status = 'pending' then
    delete from public.notifications as n
    where n.dedupe_key = 'group_join_request:' || g.id || ':' || auth.uid();
  end if;
end;
$$;

GRANT EXECUTE ON FUNCTION public.leave_group(uuid) TO authenticated;
