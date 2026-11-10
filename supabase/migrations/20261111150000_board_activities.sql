-- Board activities and announcements (MOD-07). Design document sections 7.5, 8.8, 8.9 and 10.3,
-- and FR-MOD-5. An admin marks an activity they organize as a FABA board activity, which shows a
-- badge, and can announce it once to every active member. Both go in the audit log.

ALTER TABLE public.activities
ADD COLUMN is_board_activity BOOLEAN NOT NULL DEFAULT FALSE,
ADD COLUMN announced_at timestamptz;

-- How many were announced lately, for the warning (section 6.5).
CREATE INDEX activities_announced_at_idx ON public.activities (announced_at)
WHERE announced_at IS NOT NULL;

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
      'announce_activity'
    )
  );

-- Locks and returns `activity_id` when the signed-in member is an active admin who organizes it.
CREATE FUNCTION private.board_activity(activity_id uuid)
RETURNS public.activities
LANGUAGE plpgsql
SET search_path = ''
AS $$
declare
  activity public.activities;
begin
  if not private.is_active_member() then
    raise exception 'NOT_ACTIVE' using errcode = '42501';
  end if;

  if not exists (select from public.profiles as p where p.id = auth.uid() and p.role = 'admin') then
    raise exception 'NOT_ADMIN' using errcode = '42501';
  end if;

  select * into activity from public.activities as a where a.id = board_activity.activity_id
  for update;

  -- The same for an activity that doesn't exist, so nobody learns which ones do.
  if not found or activity.organizer_id is distinct from auth.uid() then
    raise exception 'NOT_ORGANIZER' using errcode = '42501';
  end if;

  return activity;
end;
$$;

REVOKE EXECUTE
ON FUNCTION private.board_activity(uuid)
FROM PUBLIC, anon, authenticated, service_role;

-- Marks `activity_id` as a FABA board activity, or not. Only an admin who organizes it can. Setting
-- what it already is changes nothing and logs nothing.
CREATE FUNCTION public.set_board_activity(activity_id uuid, board BOOLEAN)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
declare
  activity public.activities := private.board_activity(set_board_activity.activity_id);
begin
  if activity.is_board_activity = coalesce(set_board_activity.board, false) then
    return;
  end if;

  update public.activities as a
  set is_board_activity = coalesce(set_board_activity.board, false)
  where a.id = activity.id;

  perform private.audit(
    'set_board_activity',
    'activity',
    activity.id,
    null,
    jsonb_build_object('board', coalesce(set_board_activity.board, false))
  );
end;
$$;

GRANT EXECUTE ON FUNCTION public.set_board_activity(uuid, BOOLEAN) TO authenticated;

-- Announces board activity `activity_id` to every active member but the admin, once. It has to be
-- coming up, and neither cancelled nor hidden. Muting doesn't hold it back (section 8.8). Returns
-- how many members it told.
CREATE FUNCTION public.announce_activity(activity_id uuid)
RETURNS INTEGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
declare
  activity public.activities := private.board_activity(announce_activity.activity_id);
  told integer;
begin
  if not activity.is_board_activity then
    raise exception 'NOT_BOARD_ACTIVITY' using errcode = '22023';
  end if;

  if activity.announced_at is not null then
    raise exception 'ALREADY_ANNOUNCED' using errcode = '22023';
  end if;

  if activity.status = 'cancelled' or activity.hidden_at is not null then
    raise exception 'ANNOUNCE_UNAVAILABLE' using errcode = '22023';
  end if;

  if activity.starts_at <= now() then
    raise exception 'ANNOUNCE_TOO_LATE' using errcode = '22023';
  end if;

  update public.activities as a set announced_at = now() where a.id = activity.id;

  -- One INSERT … SELECT for about 2,600 members.
  told := private.notify(
    array(
      select p.id
      from public.profiles as p
      where p.status = 'active' and p.id != auth.uid()
    ),
    'board_announcement',
    activity.id,
    jsonb_build_object('title', activity.title, 'starts_at', activity.starts_at),
    'board_announcement:' || activity.id
  );

  perform private.audit('announce_activity', 'activity', activity.id, null, jsonb_build_object('told', told));
  return told;
end;
$$;

GRANT EXECUTE ON FUNCTION public.announce_activity(uuid) TO authenticated;
