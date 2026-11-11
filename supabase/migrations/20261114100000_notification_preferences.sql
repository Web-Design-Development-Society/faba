-- Notification preferences (NOTIF-10). Design document sections 8.8, 9.12 and 10.4. A member turns
-- each notification type on or off under Me → Notifications. Only the types a member has turned
-- off have a row, so a missing row means on. Cancellations can't be turned off, so a member always
-- hears that an activity they're in is gone. Phase 5 adds rows for new channels, which needs the
-- channel check widened then.

CREATE TABLE public.notification_preferences (
  user_id uuid NOT NULL REFERENCES public.profiles (id)
    ON DELETE CASCADE,
  type text NOT NULL CHECK (
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
      'group_owner',
      'rsvp_promoted',
      'rsvp_removed'
    )
  ),
  channel text NOT NULL DEFAULT 'in_app' CHECK (channel = 'in_app'),
  enabled BOOLEAN NOT NULL DEFAULT FALSE,
  updated_at timestamptz NOT NULL DEFAULT now(),
  PRIMARY KEY (user_id, type, channel),
  CONSTRAINT cancellations_stay_on CHECK (type != 'activity_cancelled' OR enabled)
);

ALTER TABLE public.notification_preferences ENABLE ROW LEVEL SECURITY;

-- Members read their own. Nobody else can see what someone has turned off. Writes go through
-- set_notification_preferences().
CREATE POLICY "Members read their own notification preferences" ON public.notification_preferences
FOR SELECT
TO authenticated
USING (user_id = (SELECT auth.uid()));

-- Saves the signed-in member's choices: `off` is the types they've turned off. Their rows are
-- replaced, so a type that isn't in `off` is on again. Cancellations are left out, so they stay on
-- whatever is sent.
CREATE FUNCTION public.set_notification_preferences(off text[])
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
begin
  if not private.is_active_member() then
    raise exception 'NOT_ACTIVE' using errcode = '42501';
  end if;

  delete from public.notification_preferences as p
  where p.user_id = auth.uid() and p.channel = 'in_app';

  insert into public.notification_preferences (user_id, type, channel, enabled)
  select distinct auth.uid(), t.type, 'in_app', FALSE
  from unnest(set_notification_preferences.off) as t (type)
  where t.type <> 'activity_cancelled';
end;
$$;

REVOKE EXECUTE ON FUNCTION public.set_notification_preferences(text[]) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.set_notification_preferences(text[]) TO authenticated;

-- The same as before (20261109140000_mute_activity.sql, NOTIF-08), with one more filter: a member
-- who has turned a type off gets no notification of it. Cancellations have no row that turns them
-- off, so they always come.
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
    read_at = null;
  get diagnostics made = row_count;
  return made;
end;
$$;
