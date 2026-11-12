-- Channel preferences, quiet hours and reminder timing (NOTIF-13). Email delivery (NOTIF-11 and 16)
-- isn't built yet. This stores what a member chose, so that sender can respect it:
--   * a matrix of notification type by channel (in_app or email), on by default;
--   * quiet hours, when non-urgent email waits (default 9 PM to 7 AM, Boise time);
--   * how far ahead reminders come (1, 2, 6 or 24 hours).
-- Urgent changes and cancellations (NOTIF-11) aren't held by quiet hours.

CREATE TABLE public.notification_channel_settings (
  user_id uuid PRIMARY KEY REFERENCES public.profiles (id)
    ON DELETE CASCADE,
  quiet_start TIME NOT NULL DEFAULT '21:00',
  quiet_end TIME NOT NULL DEFAULT '07:00',
  reminder_lead_hours INTEGER NOT NULL DEFAULT 2 CHECK (reminder_lead_hours IN (1, 2, 6, 24)),
  updated_at timestamptz NOT NULL DEFAULT now()
);

CREATE TABLE public.notification_channel_choices (
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
      'rsvp_removed',
      'new_activity',
      'sub_needed',
      'report_received'
    )
  ),
  channel text NOT NULL CHECK (channel IN ('in_app', 'email')),
  enabled BOOLEAN NOT NULL,
  PRIMARY KEY (user_id, type, channel)
);

ALTER TABLE public.notification_channel_settings ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.notification_channel_choices ENABLE ROW LEVEL SECURITY;

-- Members read their own choices. Writes go through the functions below.
CREATE POLICY "Members read their channel settings" ON public.notification_channel_settings
FOR SELECT
TO authenticated
USING (user_id = (SELECT auth.uid()));

CREATE POLICY "Members read their channel choices" ON public.notification_channel_choices
FOR SELECT
TO authenticated
USING (user_id = (SELECT auth.uid()));

-- Saves the quiet hours and the reminder lead time. A quiet period may cross midnight.
CREATE FUNCTION public.set_channel_settings(
  quiet_start TIME,
  quiet_end TIME,
  reminder_lead_hours INTEGER
)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
begin
  if not private.is_active_member() then
    raise exception 'NOT_ACTIVE' using errcode = '42501';
  end if;

  if set_channel_settings.reminder_lead_hours not in (1, 2, 6, 24) then
    raise exception 'INVALID_LEAD_TIME' using errcode = '22023';
  end if;

  insert into public.notification_channel_settings (user_id, quiet_start, quiet_end, reminder_lead_hours, updated_at)
  values (auth.uid(), set_channel_settings.quiet_start, set_channel_settings.quiet_end, set_channel_settings.reminder_lead_hours, now())
  on conflict (user_id) do update
  set quiet_start = excluded.quiet_start,
      quiet_end = excluded.quiet_end,
      reminder_lead_hours = excluded.reminder_lead_hours,
      updated_at = excluded.updated_at;
end;
$$;

REVOKE EXECUTE ON FUNCTION public.set_channel_settings(TIME, TIME, INTEGER) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.set_channel_settings(TIME, TIME, INTEGER) TO authenticated;

-- Turns one type on or off for a channel.
CREATE FUNCTION public.set_channel_choice(type text, channel text, enabled BOOLEAN)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
begin
  if not private.is_active_member() then
    raise exception 'NOT_ACTIVE' using errcode = '42501';
  end if;

  insert into public.notification_channel_choices (user_id, type, channel, enabled)
  values (auth.uid(), set_channel_choice.type, set_channel_choice.channel, set_channel_choice.enabled)
  on conflict on constraint notification_channel_choices_pkey do update
  set enabled = excluded.enabled;
end;
$$;

REVOKE EXECUTE ON FUNCTION public.set_channel_choice(text, text, BOOLEAN) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.set_channel_choice(text, text, BOOLEAN) TO authenticated;

-- Whether `at` falls in the member's quiet hours, in Boise time. Used by the email sender.
CREATE FUNCTION private.in_quiet_hours(user_id uuid, at timestamptz)
RETURNS BOOLEAN
LANGUAGE sql
STABLE
SET search_path = ''
AS $$
  WITH
    s AS (
      SELECT
        coalesce(c.quiet_start, TIME '21:00') AS quiet_start,
        coalesce(c.quiet_end, TIME '07:00') AS quiet_end,
        (in_quiet_hours.at AT TIME ZONE 'America/Boise')::TIME AS local_time
      FROM (SELECT 1) AS one
      LEFT JOIN public.notification_channel_settings AS c ON c.user_id = in_quiet_hours.user_id
    )
  SELECT CASE
    WHEN quiet_start <= quiet_end THEN local_time >= quiet_start AND local_time < quiet_end
    ELSE local_time >= quiet_start OR local_time < quiet_end
  END
  FROM s;
$$;

REVOKE EXECUTE
ON FUNCTION private.in_quiet_hours(uuid, timestamptz)
FROM PUBLIC, anon, authenticated;
