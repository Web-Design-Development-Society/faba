-- Notifications (NOTIF-01). Design document sections 7.9, 8.8, 9.12 and 10.3, and FR-NOT-1. One
-- row per recipient, made only by private.notify() in the same transaction as the change that
-- caused it, and read only by its recipient. A row stores data, not text: the app writes the words
-- when it shows it, so email and SMS can use the same row later (Phase 5). The stories that make
-- each type, such as NOTIF-02, call private.notify().

CREATE TABLE public.notifications (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  recipient_id uuid NOT NULL REFERENCES public.profiles (id)
    ON DELETE CASCADE,
  -- The Phase 2 types in section 8.8. Later phases add theirs.
  type text NOT NULL CHECK (
    type IN (
      'activity_changed',
      'activity_cancelled',
      'activity_restored',
      'organizer_update',
      'rsvp_confirmed',
      'new_attendees',
      'reminder',
      'board_announcement'
    )
  ),
  -- The notification stays when its activity goes, and opens "no longer available".
  activity_id uuid REFERENCES public.activities (id)
    ON DELETE SET NULL,
  actor_id uuid REFERENCES public.profiles (id)
    ON DELETE SET NULL,
  -- A snapshot, such as the activity's title and its old and new times.
  payload jsonb NOT NULL DEFAULT '{}',
  -- Repeat changes with the same key make one notification for each recipient.
  dedupe_key text,
  read_at timestamptz,
  created_at timestamptz NOT NULL DEFAULT now(),
  UNIQUE (recipient_id, dedupe_key)
);

CREATE INDEX notifications_recipient_idx
ON public.notifications (recipient_id, created_at DESC, id DESC);

-- The unread count, which the badge asks for on every page and every minute.
CREATE INDEX notifications_unread_idx ON public.notifications (recipient_id)
WHERE read_at IS NULL;

CREATE INDEX notifications_activity_idx ON public.notifications (activity_id);

CREATE INDEX notifications_actor_idx ON public.notifications (actor_id);

ALTER TABLE public.notifications ENABLE ROW LEVEL SECURITY;

-- Section 9.8: members read their own. They mark them read through mark_notifications_read().
CREATE POLICY "Members read their own notifications" ON public.notifications
FOR SELECT
TO authenticated
USING (recipient_id = (SELECT auth.uid()));

-- Makes a notification of `type` for each of `recipients`, about `activity_id`, with the signed-in
-- member as its actor. It's the only way notifications are made (section 9.12), and only other
-- database functions call it. With a `dedupe_key`, a recipient's earlier notification with the same
-- key comes back as new and unread with this payload, so repeat edits make one notification.
-- Returns how many it made or brought back.
CREATE FUNCTION private.notify(
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
  where r.id is not null
  on conflict on constraint notifications_recipient_id_dedupe_key_key do update
  set
    payload = excluded.payload,
    actor_id = excluded.actor_id,
    created_at = now(),
    read_at = null;
  get diagnostics made = row_count;
  return made;
end;
$$;

REVOKE EXECUTE
ON FUNCTION private.notify(uuid[], text, uuid, jsonb, text)
FROM PUBLIC, anon, authenticated, service_role;

-- Marks the signed-in member's notifications read: the ones in `ids`, or all of them. Returns how
-- many it marked.
CREATE FUNCTION public.mark_notifications_read(ids uuid[] DEFAULT NULL)
RETURNS INTEGER
LANGUAGE sql
SECURITY DEFINER
SET search_path = ''
AS $$
  WITH
    marked AS (
      UPDATE public.notifications
      SET read_at = now()
      WHERE recipient_id = auth.uid() AND read_at IS NULL AND (ids IS NULL OR id = ANY (ids))
      RETURNING 1
    )
  SELECT count(*)::INTEGER
  FROM marked;
$$;

GRANT EXECUTE ON FUNCTION public.mark_notifications_read(uuid[]) TO authenticated;

-- The session context as before (20261101120000_guidelines_and_session_context.sql), with the
-- unread count, so every page can show it (section 9.7, step 6).
DROP FUNCTION public.get_session_context();

CREATE FUNCTION public.get_session_context()
RETURNS TABLE (
  status text,
  role text,
  display_name text,
  avatar_url text,
  use_initials BOOLEAN,
  guidelines_ok BOOLEAN,
  unread_count INTEGER
)
LANGUAGE sql
STABLE
SET search_path = ''
AS $$
  SELECT
    status,
    role,
    display_name,
    avatar_url,
    use_initials,
    coalesce(guidelines_version >= private.guidelines_version(), FALSE),
    (
      SELECT count(*)::INTEGER
      FROM public.notifications AS n
      WHERE n.recipient_id = auth.uid() AND n.read_at IS NULL
    )
  FROM public.profiles
  WHERE id = auth.uid();
$$;

GRANT EXECUTE ON FUNCTION public.get_session_context() TO authenticated;

-- Deletes what FABA keeps for a limited time: notifications after 90 days (NOTIF-01). Later
-- stories add to it, such as ACT-09's private details. Returns how many rows it deleted.
CREATE FUNCTION private.purge_old_data()
RETURNS INTEGER
LANGUAGE sql
SET search_path = ''
AS $$
  WITH
    gone AS (
      DELETE FROM public.notifications
      WHERE created_at < now() - INTERVAL '90 days'
      RETURNING 1
    )
  SELECT count(*)::INTEGER
  FROM gone;
$$;

REVOKE EXECUTE ON FUNCTION private.purge_old_data() FROM PUBLIC, anon, authenticated, service_role;

-- Scheduled jobs run in the database with pg_cron (section 9.12). This one runs at 10:30 UTC, which
-- is 3:30 or 4:30 AM in Rexburg.
CREATE EXTENSION IF NOT EXISTS pg_cron WITH SCHEMA pg_catalog;

SELECT cron.schedule('purge-old-data', '30 10 * * *', 'select private.purge_old_data()');
