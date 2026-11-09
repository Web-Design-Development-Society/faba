-- Telling attendees when an activity is cancelled or back on (NOTIF-03). Design document sections
-- 7.9 and 8.8. Whoever cancels it, everyone going or maybe gets activity_cancelled, with the reason,
-- and restoring it sends activity_restored. RSVPs stay when an activity is cancelled, so those are
-- the people who were going or maybe. The person who did it isn't told. Muting (NOTIF-08) won't hold
-- these back. Each is made in the same transaction as the change.

-- Notifies everyone going or maybe to `activity_id`, but the signed-in member, with `type` and
-- `payload`. Returns how many it notified.
CREATE FUNCTION private.notify_attendees(activity_id uuid, type text, payload jsonb)
RETURNS INTEGER
LANGUAGE sql
SET search_path = ''
AS $$
  SELECT private.notify(
    ARRAY(
      SELECT r.user_id
      FROM public.rsvps AS r
      JOIN public.profiles AS p ON p.id = r.user_id
      WHERE
        r.activity_id = notify_attendees.activity_id
        AND r.status IN ('going', 'maybe')
        AND r.user_id IS DISTINCT FROM auth.uid()
        AND p.status = 'active'
    ),
    notify_attendees.type,
    notify_attendees.activity_id,
    notify_attendees.payload
  );
$$;

REVOKE EXECUTE
ON FUNCTION private.notify_attendees(uuid, text, jsonb)
FROM PUBLIC, anon, authenticated, service_role;

-- An organizer cancelling, and restoring, as before (20261104130000_cancel_activity.sql).
CREATE OR REPLACE FUNCTION public.cancel_activity(activity_id uuid, reason text DEFAULT NULL)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
declare
  activity public.activities;
begin
  if not private.is_active_member() then
    raise exception 'NOT_ACTIVE' using errcode = '42501';
  end if;

  select * into activity
  from public.activities as a
  where a.id = cancel_activity.activity_id
  for update;

  -- The same for an activity that doesn't exist, so nobody learns which ones do.
  if not found or activity.organizer_id is distinct from auth.uid() then
    raise exception 'NOT_ORGANIZER' using errcode = '42501';
  end if;

  if activity.status = 'cancelled' then
    return;
  end if;

  update public.activities as a
  set
    status = 'cancelled',
    cancel_reason = nullif(trim(cancel_activity.reason), ''),
    cancelled_at = now()
  where a.id = activity.id;

  perform private.notify_attendees(
    activity.id,
    'activity_cancelled',
    jsonb_build_object(
      'title', activity.title,
      'starts_at', activity.starts_at,
      'reason', nullif(trim(cancel_activity.reason), '')
    )
  );
end;
$$;

CREATE OR REPLACE FUNCTION public.restore_activity(activity_id uuid)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
declare
  activity public.activities;
begin
  if not private.is_active_member() then
    raise exception 'NOT_ACTIVE' using errcode = '42501';
  end if;

  select * into activity
  from public.activities as a
  where a.id = restore_activity.activity_id
  for update;

  if not found or activity.organizer_id is distinct from auth.uid() then
    raise exception 'NOT_ORGANIZER' using errcode = '42501';
  end if;

  if activity.status = 'published' then
    return;
  end if;

  if activity.starts_at <= now() then
    raise exception 'RESTORE_TOO_LATE' using errcode = '22023';
  end if;

  update public.activities as a
  set status = 'published', cancel_reason = null, cancelled_at = null
  where a.id = activity.id;

  perform private.notify_attendees(
    activity.id,
    'activity_restored',
    jsonb_build_object('title', activity.title, 'starts_at', activity.starts_at)
  );
end;
$$;

-- A moderator cancelling for an organizer who's no longer eligible, as before
-- (20261106130000_hand_over_activity.sql).
CREATE OR REPLACE FUNCTION public.moderate_cancel_activity(activity_id uuid, reason text)
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

  perform private.notify_attendees(
    activity.id,
    'activity_cancelled',
    jsonb_build_object(
      'title', activity.title,
      'starts_at', activity.starts_at,
      'reason', 'Its organizer is no longer active.'
    )
  );

  perform private.audit(
    'cancel_activity',
    'activity',
    activity.id,
    moderate_cancel_activity.reason,
    jsonb_build_object('going_count', activity.going_count)
  );
end;
$$;

-- Deleting an account, as before (20261106240000_guest_counts.sql). Each activity it cancels tells
-- its attendees.
CREATE OR REPLACE FUNCTION public.delete_my_account()
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
declare
  cancelled integer := 0;
  removed integer;
  gone record;
begin
  if not exists (select from public.profiles as p where p.id = auth.uid()) then
    raise exception 'ACCOUNT_NOT_FOUND' using errcode = 'P0002';
  end if;

  -- Activities they organize that haven't started. Their attendees still find them, cancelled, and
  -- hear about it (NOTIF-03).
  for gone in
    update public.activities as a
    set status = 'cancelled', cancel_reason = 'Its organizer left FABA.', cancelled_at = now()
    where a.organizer_id = auth.uid() and a.status = 'published' and a.starts_at > now()
    returning a.id, a.title, a.starts_at
  loop
    cancelled := cancelled + 1;
    perform private.notify_attendees(
      gone.id,
      'activity_cancelled',
      jsonb_build_object(
        'title', gone.title,
        'starts_at', gone.starts_at,
        'reason', 'Its organizer left FABA.'
      )
    );
  end loop;

  -- Their RSVPs, with the going and maybe counts and the guests that rsvp() keeps (ADR-008).
  update public.activities as a
  set
    going_count = a.going_count - (r.status = 'going')::integer,
    maybe_count = a.maybe_count - (r.status = 'maybe')::integer,
    guest_total = a.guest_total - r.guest_count
  from public.rsvps as r
  where r.activity_id = a.id and r.user_id = auth.uid() and r.status in ('going', 'maybe');

  delete from public.rsvps as r
  where r.user_id = auth.uid();
  get diagnostics removed = row_count;

  perform private.audit(
    'delete_account',
    'profile',
    auth.uid(),
    NULL,
    jsonb_build_object('activities_cancelled', cancelled, 'rsvps_removed', removed)
  );
end;
$$;
