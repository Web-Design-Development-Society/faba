-- FABA keeps every notification in the app, under Alerts, to encourage faculty to use it. It won't
-- send email or SMS, so NOTIF-11, 12 and 14 to 18 are closed as not planned. The email settings on
-- Me → Notifications (NOTIF-13) never had a sender to apply them, so they go, with the tables and
-- functions that stored them. The per-type in-app switches (notification_preferences, NOTIF-10)
-- stay.

DROP FUNCTION private.in_quiet_hours(uuid, timestamptz);
DROP FUNCTION public.set_channel_choice(text, text, BOOLEAN);
DROP FUNCTION public.set_channel_settings(TIME, TIME, INTEGER);

DROP TABLE public.notification_channel_choices;
DROP TABLE public.notification_channel_settings;
