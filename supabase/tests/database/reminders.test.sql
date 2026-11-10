-- In-app reminders (NOTIF-07). Run with `npm run db:test`.
BEGIN;

CREATE EXTENSION IF NOT EXISTS pgtap WITH SCHEMA extensions;

SELECT plan(14);

-- Ola organizes, Gus is going, May is a maybe, Mo muted, Lee said I'm in late, and Sid is
-- suspended.
INSERT INTO auth.users
  (id, email, raw_user_meta_data)
SELECT
  ('c0000000-0000-4000-8000-00000000038' || n)::uuid,
  name || '@byui.edu',
  jsonb_build_object('full_name', name)
FROM (
  VALUES
    (1, 'ola'),
    (2, 'gus'),
    (3, 'may'),
    (4, 'mo'),
    (5, 'lee'),
    (6, 'sid')
) AS v (n, name);

UPDATE public.profiles
SET
  guidelines_version = 1,
  guidelines_accepted_at = now()
WHERE id::text LIKE 'c0000000-0000-4000-8000-00000000038_';

-- Friday, November 20, 2026, in Rexburg (MST, UTC-7).
INSERT INTO public.activities
  (id, organizer_id, category_id, title, starts_at, location_name, status, hidden_at)
VALUES
  (
    'f0000000-0000-4000-8000-000000000381',
    'c0000000-0000-4000-8000-000000000381',
    'sports',
    'Lunch pickleball',
    '2026-11-20 12:10-07',
    'Hart courts',
    'published',
    NULL
  ),
  (
    'f0000000-0000-4000-8000-000000000382',
    'c0000000-0000-4000-8000-000000000381',
    'games',
    'Board game night',
    '2026-11-20 19:00-07',
    'Library',
    'published',
    NULL
  ),
  (
    'f0000000-0000-4000-8000-000000000383',
    'c0000000-0000-4000-8000-000000000381',
    'outdoors',
    'Sunrise hike',
    '2026-11-20 06:30-07',
    'R Mountain',
    'published',
    NULL
  ),
  (
    'f0000000-0000-4000-8000-000000000384',
    'c0000000-0000-4000-8000-000000000381',
    'games',
    'Cancelled',
    '2026-11-20 19:00-07',
    'Here',
    'published',
    NULL
  ),
  (
    'f0000000-0000-4000-8000-000000000385',
    'c0000000-0000-4000-8000-000000000381',
    'games',
    'Hidden',
    '2026-11-20 19:00-07',
    'Here',
    'published',
    '2026-11-19 12:00-07'
  );

-- Everyone answered on Thursday, but Lee said I'm in to pickleball at 7:30 AM on Friday.
INSERT INTO public.rsvps
  (activity_id, user_id, status, updated_at)
SELECT
  a.id,
  ('c0000000-0000-4000-8000-00000000038' || m.n)::uuid,
  m.status,
  CASE
    WHEN m.n = 5 AND a.id = 'f0000000-0000-4000-8000-000000000381' THEN '2026-11-20 07:30-07'
    ELSE '2026-11-19 12:00-07'
  END::timestamptz
FROM public.activities AS a
CROSS JOIN (
  VALUES
    (1, 'going'),
    (2, 'going'),
    (3, 'maybe'),
    (4, 'going'),
    (5, 'going'),
    (6, 'going')
) AS m (n, status)
WHERE a.id::text LIKE 'f0000000-0000-4000-8000-00000000038_';

INSERT INTO public.activity_mutes
  (activity_id, user_id)
SELECT
  id,
  'c0000000-0000-4000-8000-000000000384'
FROM public.activities
WHERE id::text LIKE 'f0000000-0000-4000-8000-00000000038_';

UPDATE public.activities
SET
  status = 'cancelled',
  cancelled_at = '2026-11-19 12:00-07'
WHERE id = 'f0000000-0000-4000-8000-000000000384';

UPDATE public.profiles
SET status = 'suspended'
WHERE id = 'c0000000-0000-4000-8000-000000000386';

-- Other activities, such as the seed's, are hidden until the test rolls back, so only these are due.
UPDATE public.activities
SET hidden_at = now()
WHERE id::text NOT LIKE 'f0000000-0000-4000-8000-00000000038_' AND hidden_at IS NULL;

-- Who has a reminder for which activity.
CREATE VIEW pg_temp.reminded AS
  SELECT
    a.title,
    p.display_name AS member
  FROM public.notifications AS n
  JOIN public.activities AS a ON a.id = n.activity_id
  JOIN public.profiles AS p ON p.id = n.recipient_id
  WHERE n.type = 'reminder';

-- When each is due.
SELECT results_eq(
  $$
    select title, private.reminder_at(starts_at, timezone) at time zone 'America/Denver'
    from public.activities as a
    where id::text like 'f0000000-0000-4000-8000-00000000038_' and id::text < 'f0000000-0000-4000-8000-000000000384'
    order by starts_at
  $$,
  $$values
    ('Sunrise hike', '2026-11-20 04:30'::timestamp),
    ('Lunch pickleball', '2026-11-20 07:00'),
    ('Board game night', '2026-11-20 17:00')$$,
  'before 1 PM is 7 AM that day, 1 PM or later is 2 hours before, and before 7 AM is 2 hours before'
);

SELECT results_eq(
  $$select private.reminder_at('2026-11-20 13:00-07', 'America/Denver') at time zone 'America/Denver'$$,
  $$values ('2026-11-20 11:00'::timestamp)$$,
  '1 PM is 2 hours before'
);

SELECT results_eq(
  $$select private.reminder_at('2026-07-10 10:00-06', 'America/Denver') at time zone 'America/Denver'$$,
  $$values ('2026-07-10 07:00'::timestamp)$$,
  'and 7 AM is in summer time too'
);

SELECT results_eq(
  $$select private.send_reminders('2026-11-20 04:15-07')$$,
  $$values (0)$$,
  'nothing is due before its time'
);

SELECT results_eq(
  $$select private.send_reminders('2026-11-20 04:30-07')$$,
  $$values (3)$$,
  'at its time, the hike reminds three'
);

SELECT results_eq(
  $$select member from pg_temp.reminded order by member$$,
  $$values ('gus'), ('lee'), ('ola')$$,
  'the organizer and those going, but not a maybe, someone muted or someone suspended'
);

SELECT results_eq(
  $$select private.send_reminders('2026-11-20 06:59-07')$$,
  $$values (0)$$,
  'once each, and none once it starts'
);

SELECT results_eq(
  $$select private.send_reminders('2026-11-20 07:00-07')$$,
  $$values (2)$$,
  'pickleball reminds at 7 AM'
);

SELECT results_eq(
  $$select member from pg_temp.reminded where title = 'Lunch pickleball' order by member$$,
  $$values ('gus'), ('ola')$$,
  'but not Lee, who said I''m in after 7 AM'
);

SELECT results_eq(
  $$select private.send_reminders('2026-11-20 07:15-07')$$,
  $$values (0)$$,
  'the next run makes no more'
);

-- The organizer moves board game night to 6 PM after the 5 PM reminder.
SELECT results_eq(
  $$select private.send_reminders('2026-11-20 17:20-07')$$,
  $$values (3)$$,
  'a run that comes late still sends them'
);

UPDATE public.activities
SET starts_at = '2026-11-20 20:00-07'
WHERE id = 'f0000000-0000-4000-8000-000000000382';

SELECT results_eq(
  $$select private.send_reminders('2026-11-20 18:00-07')$$,
  $$values (0)$$,
  'a new time doesn''t send another'
);

SELECT results_eq(
  $$
    select count(*)::integer, bool_and(read_at is null), bool_and(actor_id is null)
    from public.notifications
    where type = 'reminder'
  $$,
  $$values (8, true, true)$$,
  'they''re unread, with no actor'
);

SELECT results_eq(
  $$
    select payload ->> 'title', payload ->> 'location_name', (payload ->> 'starts_at')::timestamptz
    from public.notifications
    where type = 'reminder' and activity_id = 'f0000000-0000-4000-8000-000000000381'
    limit 1
  $$,
  $$values ('Lunch pickleball', 'Hart courts', '2026-11-20 12:10-07'::timestamptz)$$,
  'with the title, place and time'
);

SELECT *
FROM finish();

ROLLBACK;
