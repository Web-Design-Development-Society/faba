-- Muting an activity (NOTIF-08). Run with `npm run db:test`.
BEGIN;

CREATE EXTENSION IF NOT EXISTS pgtap WITH SCHEMA extensions;

SELECT plan(14);

-- Ora organizes board games. Gia is going, May is a maybe, Nat can't make it, and Ava hasn't
-- answered. Gia moves to a new account, Neo, at the end.
INSERT INTO auth.users
  (id, email, raw_user_meta_data)
SELECT
  ('c0000000-0000-4000-8000-00000000032' || n)::uuid,
  name || '@byui.edu',
  jsonb_build_object('full_name', name)
FROM (
  VALUES
    (1, 'ora'),
    (2, 'gia'),
    (3, 'may'),
    (4, 'nat'),
    (5, 'ava'),
    (6, 'neo')
) AS v (n, name);

UPDATE public.profiles
SET
  guidelines_version = 1,
  guidelines_accepted_at = now()
WHERE id::text LIKE 'c0000000-0000-4000-8000-00000000032_';

INSERT INTO public.activities
  (id, organizer_id, category_id, title, starts_at, location_name, going_count, maybe_count)
VALUES
  (
    'f0000000-0000-4000-8000-000000000321',
    'c0000000-0000-4000-8000-000000000321',
    'games',
    'Board games',
    now() + INTERVAL '2 days',
    'Here',
    2,
    1
  );

INSERT INTO public.rsvps
  (activity_id, user_id, status)
SELECT
  'f0000000-0000-4000-8000-000000000321',
  ('c0000000-0000-4000-8000-00000000032' || member)::uuid,
  status
FROM (
  VALUES
    ('1', 'going'),
    ('2', 'going'),
    ('3', 'maybe'),
    ('4', 'not_going')
) AS v (member, status);

-- Who has a notification of `type` about the games, read as the database owner.
CREATE FUNCTION pg_temp.sent(type text)
RETURNS SETOF text
LANGUAGE sql
AS $$
  SELECT right(recipient_id::text, 1)
  FROM public.notifications
  WHERE activity_id = 'f0000000-0000-4000-8000-000000000321' AND notifications.type = sent.type
  ORDER BY recipient_id;
$$;

-- Ora moves the games.
CREATE FUNCTION pg_temp.move(place text)
RETURNS void
LANGUAGE sql
AS $$
  SELECT public.update_activity(
    'f0000000-0000-4000-8000-000000000321',
    jsonb_build_object('location_name', place),
    (SELECT version FROM public.activities WHERE id = 'f0000000-0000-4000-8000-000000000321')
  );
$$;

CREATE FUNCTION pg_temp.as_member(n INTEGER)
RETURNS void
LANGUAGE sql
AS $$
  SELECT set_config(
    'request.jwt.claims',
    jsonb_build_object(
      'sub',
      'c0000000-0000-4000-8000-00000000032' || n,
      'email',
      'm@byui.edu'
    )::text,
    TRUE
  );
$$;

GRANT EXECUTE ON ALL FUNCTIONS IN SCHEMA pg_temp TO authenticated;

SET LOCAL ROLE anon;

SELECT throws_ok(
  'select from public.activity_mutes',
  '42501',
  NULL,
  'signed-out visitors can''t read mutes'
);

SET LOCAL ROLE authenticated;

SELECT pg_temp.as_member(2);

SELECT public.mute_activity('f0000000-0000-4000-8000-000000000321', TRUE);

SELECT public.mute_activity('f0000000-0000-4000-8000-000000000321', TRUE);

SELECT results_eq(
  'select activity_id from public.activity_mutes',
  $$values ('f0000000-0000-4000-8000-000000000321'::uuid)$$,
  'a member going mutes an activity, once however often they tap, and reads that they did'
);

SELECT throws_ok(
  $$insert into public.activity_mutes (activity_id, user_id)
  values ('f0000000-0000-4000-8000-000000000321', 'c0000000-0000-4000-8000-000000000323')$$,
  '42501',
  NULL,
  'members can''t write mutes directly'
);

SELECT pg_temp.as_member(4);

SELECT throws_ok(
  $$select public.mute_activity('f0000000-0000-4000-8000-000000000321', true)$$,
  '22023',
  'NOT_ATTENDING',
  'a member who can''t make it has nothing to mute'
);

SELECT pg_temp.as_member(5);

SELECT throws_ok(
  $$select public.mute_activity('f0000000-0000-4000-8000-000000000321', true)$$,
  '22023',
  'NOT_ATTENDING',
  'nor does one who hasn''t answered'
);

SELECT pg_temp.as_member(1);

SELECT lives_ok(
  $$select public.mute_activity('f0000000-0000-4000-8000-000000000321', true)$$,
  'the organizer can mute their own activity'
);

SELECT public.mute_activity('f0000000-0000-4000-8000-000000000321', FALSE);

SELECT is_empty('select from public.activity_mutes', 'and unmute it');

SELECT is_empty(
  $$select from public.activity_mutes where user_id = 'c0000000-0000-4000-8000-000000000322'$$,
  'the organizer can''t see who muted their activity'
);

SELECT pg_temp.move('Room 2');

RESET ROLE;

SELECT results_eq(
  $$select pg_temp.sent('activity_changed')$$,
  $$values ('3')$$,
  'a member who muted hears nothing about a change, and the others still do'
);

SELECT results_eq(
  $$select type, private.notify(
    array['c0000000-0000-4000-8000-000000000322', 'c0000000-0000-4000-8000-000000000323']::uuid[],
    type,
    'f0000000-0000-4000-8000-000000000321',
    '{}'
  ) from unnest(array[
    'organizer_update', 'new_attendees', 'reminder', 'activity_restored', 'board_announcement'
  ]) as type$$,
  $$values
    ('organizer_update', 1),
    ('new_attendees', 1),
    ('reminder', 1),
    ('activity_restored', 2),
    ('board_announcement', 2)$$,
  'muting holds back updates, new attendees and reminders, but not other types'
);

SET LOCAL ROLE authenticated;

SELECT pg_temp.as_member(2);

SELECT public.mute_activity('f0000000-0000-4000-8000-000000000321', FALSE);

SELECT pg_temp.as_member(1);

SELECT pg_temp.move('Room 3');

RESET ROLE;

SELECT results_eq(
  $$select pg_temp.sent('activity_changed')$$,
  $$values ('2'), ('3')$$,
  'after unmuting, they hear about changes again'
);

SET LOCAL ROLE authenticated;

SELECT pg_temp.as_member(2);

SELECT public.mute_activity('f0000000-0000-4000-8000-000000000321', TRUE);

SELECT pg_temp.as_member(1);

SELECT public.cancel_activity('f0000000-0000-4000-8000-000000000321', 'Snowed in');

RESET ROLE;

SELECT results_eq(
  $$select pg_temp.sent('activity_cancelled')$$,
  $$values ('2'), ('3')$$,
  'a member who muted still hears that it''s cancelled'
);

SELECT private.transfer_account(
  'c0000000-0000-4000-8000-000000000322',
  'c0000000-0000-4000-8000-000000000326',
  'Gia has a new account'
);

SELECT results_eq(
  'select right(user_id::text, 1) from public.activity_mutes',
  $$values ('6')$$,
  'a mute moves to a new account with the RSVP'
);

SELECT function_privs_are(
  'public',
  'mute_activity',
  ARRAY['uuid', 'boolean'],
  'anon',
  ARRAY[]::text[],
  'signed-out visitors can''t mute'
);

SELECT *
FROM finish();

ROLLBACK;
