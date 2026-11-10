-- In-app reminders (NOTIF-07). Design document sections 7.9, 8.8 and 9.12. A pg_cron job every 15
-- minutes reminds everyone going, the organizer among them, before an activity:
-- - Starting before 1 PM: at 7 AM that day, in the activity's time zone. One starting at 7 AM or
--   earlier gets it 2 hours before instead, so it comes before the start.
-- - Starting at 1 PM or later: 2 hours before.
-- A run reminds anyone whose reminder time has passed, as long as the activity hasn't started, so a
-- late run still sends them. Someone who said "I'm in" after their reminder time doesn't get one,
-- since they've just seen it. Each member gets at most one for each activity, even if its time
-- changes. Cancelled and hidden activities, and suspended members, get none, and private.notify()
-- leaves out members who muted it (NOTIF-08).

-- When the reminder is due for an activity that starts at `starts_at` in `timezone`.
CREATE FUNCTION private.reminder_at(starts_at timestamptz, timezone text)
RETURNS timestamptz
LANGUAGE sql
STABLE
SET search_path = ''
AS $$
  SELECT CASE
    WHEN
      (starts_at AT TIME ZONE timezone)::TIME > '07:00'
      AND (starts_at AT TIME ZONE timezone)::TIME < '13:00'
    THEN
      (
        date_trunc('day', starts_at AT TIME ZONE timezone) + INTERVAL '7 hours'
      ) AT TIME ZONE timezone
    ELSE starts_at - INTERVAL '2 hours'
  END;
$$;

REVOKE EXECUTE
ON FUNCTION private.reminder_at(timestamptz, text)
FROM PUBLIC, anon, authenticated, service_role;

-- Reminds everyone due a reminder at `as_of`, which tests can set. Returns how many it made.
CREATE FUNCTION private.send_reminders(as_of timestamptz DEFAULT now())
RETURNS INTEGER
LANGUAGE plpgsql
SET search_path = ''
AS $$
declare
  activity public.activities;
  made integer := 0;
begin
  -- A reminder is never more than 6 hours before the start, so only those starting soon are due.
  for activity in
    select a.*
    from public.activities as a
    where
      a.starts_at > as_of
      and a.starts_at <= as_of + interval '6 hours'
      and a.status = 'published'
      and a.hidden_at is null
      and private.reminder_at(a.starts_at, a.timezone) <= as_of
  loop
    made := made + private.notify(
      array(
        select r.user_id
        from public.rsvps as r
        join public.profiles as p on p.id = r.user_id
        where
          r.activity_id = activity.id
          and r.status = 'going'
          and r.updated_at <= private.reminder_at(activity.starts_at, activity.timezone)
          and p.status = 'active'
          and not exists (
            select from public.notifications as n
            where n.recipient_id = r.user_id and n.dedupe_key = 'reminder:' || activity.id
          )
      ),
      'reminder',
      activity.id,
      jsonb_build_object(
        'title', activity.title,
        'starts_at', activity.starts_at,
        'location_name', activity.location_name
      ),
      'reminder:' || activity.id
    );
  end loop;
  return made;
end;
$$;

REVOKE EXECUTE
ON FUNCTION private.send_reminders(timestamptz)
FROM PUBLIC, anon, authenticated, service_role;

SELECT cron.schedule('send-reminders', '*/15 * * * *', 'select private.send_reminders()');
