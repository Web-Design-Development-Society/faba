-- Remove alerts (NOTIF-21). A member can remove an alert they're done with, or clear every one
-- they've read, so Alerts stays short. A removed alert is hidden, not deleted: the reminder job and
-- the 10-minute window for changes look for the alert that was already sent, and deleting it would
-- send the same reminder again. The nightly job deletes it with the rest after 90 days.

-- When the member removed it. Removed ones aren't listed.
ALTER TABLE public.notifications ADD COLUMN removed_at timestamptz;

-- Removes the signed-in member's notifications in `ids`, and marks them read, so the badge counts
-- only what's listed. Another member's ids change nothing. Returns how many it removed.
CREATE FUNCTION public.remove_notifications(ids uuid[])
RETURNS INTEGER
LANGUAGE sql
SECURITY DEFINER
SET search_path = ''
AS $$
  WITH
    removed AS (
      UPDATE public.notifications
      SET
        removed_at = now(),
        read_at = coalesce(read_at, now())
      WHERE recipient_id = auth.uid() AND removed_at IS NULL AND id = ANY (ids)
      RETURNING 1
    )
  SELECT count(*)::INTEGER
  FROM removed;
$$;

REVOKE EXECUTE ON FUNCTION public.remove_notifications(uuid[]) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.remove_notifications(uuid[]) TO authenticated;

-- Removes every notification the signed-in member has read: Earlier's Clear. Unread ones stay, so
-- a cancellation can't be cleared before it's seen. Returns how many it removed.
CREATE FUNCTION public.clear_read_notifications()
RETURNS INTEGER
LANGUAGE sql
SECURITY DEFINER
SET search_path = ''
AS $$
  WITH
    removed AS (
      UPDATE public.notifications
      SET removed_at = now()
      WHERE recipient_id = auth.uid() AND removed_at IS NULL AND read_at IS NOT NULL
      RETURNING 1
    )
  SELECT count(*)::INTEGER
  FROM removed;
$$;

REVOKE EXECUTE ON FUNCTION public.clear_read_notifications() FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.clear_read_notifications() TO authenticated;

-- The same as before (20261114100000_notification_preferences.sql, NOTIF-10), except that a
-- repeat brings back a removed notification too, as new.
CREATE OR REPLACE FUNCTION private.notify(
  recipients uuid[],
  type text,
  activity_id uuid,
  payload jsonb,
  dedupe_key text DEFAULT NULL
)
RETURNS INTEGER
LANGUAGE plpgsql
SET search_path = ''
AS $$
declare
  made integer;
begin
  insert into public.notifications (recipient_id, type, activity_id, actor_id, payload, dedupe_key)
  select distinct
    r.id,
    notify.type,
    notify.activity_id,
    auth.uid(),
    coalesce(notify.payload, '{}'),
    notify.dedupe_key
  from unnest(notify.recipients) as r (id)
  where
    r.id is not null
    and not (
      notify.type in ('activity_changed', 'organizer_update', 'new_attendees', 'reminder')
      and exists (
        select from public.activity_mutes as m
        where m.activity_id = notify.activity_id and m.user_id = r.id
      )
    )
    and not exists (
      select from public.notification_preferences as p
      where
        p.user_id = r.id
        and p.type = notify.type
        and p.channel = 'in_app'
        and not p.enabled
    )
  on conflict on constraint notifications_recipient_id_dedupe_key_key do update
  set
    payload = excluded.payload || jsonb_strip_nulls(
      jsonb_build_object(
        'before', notifications.payload -> 'before',
        'details_changed', notifications.payload -> 'details_changed'
      )
    ),
    actor_id = excluded.actor_id,
    created_at = now(),
    read_at = null,
    removed_at = null;
  get diagnostics made = row_count;
  return made;
end;
$$;
