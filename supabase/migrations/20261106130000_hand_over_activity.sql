-- Handing over an ineligible organizer's activities (AUTH-05). Design document section 9.7: when an
-- organizer's address is no longer byui.edu, their upcoming activities stay up, marked "Organizer
-- no longer active", and moderators can transfer or cancel them. Both write to the audit log
-- (MOD-05).

-- The audit log's two new actions.
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
      'cancel_activity'
    )
  );

-- The activity a moderator can hand over, locked: its organizer is no longer eligible, and it's on
-- and hasn't started. Checks who's asking and the reason first, like moderate_hide().
CREATE FUNCTION private.lock_handover(activity_id uuid, reason text)
RETURNS public.activities
LANGUAGE plpgsql
SET search_path = ''
AS $$
declare
  activity public.activities;
begin
  if not private.is_moderator() then
    raise exception 'NOT_MODERATOR' using errcode = '42501';
  end if;

  if nullif(trim(lock_handover.reason), '') is null then
    raise exception 'REASON_REQUIRED' using errcode = '22023';
  end if;

  select * into activity
  from public.activities as a
  where a.id = lock_handover.activity_id
  for update;

  if not found then
    raise exception 'ACTIVITY_NOT_FOUND' using errcode = 'P0002';
  end if;

  if not exists (
    select from public.profiles as p
    where p.id = activity.organizer_id and p.status = 'ineligible'
  ) then
    raise exception 'ORGANIZER_ELIGIBLE' using errcode = '22023';
  end if;

  if activity.status <> 'published' or activity.starts_at <= now() then
    raise exception 'ACTIVITY_NOT_UPCOMING' using errcode = '22023';
  end if;

  return activity;
end;
$$;

REVOKE EXECUTE
ON FUNCTION private.lock_handover(uuid, text)
FROM PUBLIC, anon, authenticated, service_role;

-- Gives the activity to a member who's going and has agreed to host it, with a reason for the
-- audit log. Only moderators and admins can. The new organizer was going already, so the count
-- stays the same, and like any organizer they stay going (rsvp()).
CREATE FUNCTION public.moderate_transfer_activity(activity_id uuid, to_user uuid, reason text)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
declare
  activity public.activities;
begin
  activity := private.lock_handover(
    moderate_transfer_activity.activity_id,
    moderate_transfer_activity.reason
  );

  if not exists (
    select from public.rsvps as r
    join public.profiles as p on p.id = r.user_id
    where
      r.activity_id = activity.id
      and r.user_id = moderate_transfer_activity.to_user
      and r.status = 'going'
      and p.status = 'active'
  ) then
    raise exception 'NEW_HOST_NOT_GOING' using errcode = '22023';
  end if;

  update public.activities as a
  set organizer_id = moderate_transfer_activity.to_user
  where a.id = activity.id;

  perform private.audit(
    'transfer_activity',
    'activity',
    activity.id,
    moderate_transfer_activity.reason,
    jsonb_build_object('from', activity.organizer_id, 'to', moderate_transfer_activity.to_user)
  );
end;
$$;

-- Cancels the activity, with a reason for the audit log. Only moderators and admins can. The
-- people going see it's cancelled, and that its organizer is no longer active.
CREATE FUNCTION public.moderate_cancel_activity(activity_id uuid, reason text)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
declare
  activity public.activities;
begin
  activity := private.lock_handover(
    moderate_cancel_activity.activity_id,
    moderate_cancel_activity.reason
  );

  update public.activities as a
  set
    status = 'cancelled',
    cancel_reason = 'Its organizer is no longer active.',
    cancelled_at = now()
  where a.id = activity.id;

  perform private.audit(
    'cancel_activity',
    'activity',
    activity.id,
    moderate_cancel_activity.reason,
    jsonb_build_object('going_count', activity.going_count)
  );
end;
$$;

GRANT EXECUTE ON FUNCTION public.moderate_transfer_activity(uuid, uuid, text) TO authenticated;

GRANT EXECUTE ON FUNCTION public.moderate_cancel_activity(uuid, text) TO authenticated;
