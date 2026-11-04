-- Editing an activity (ACT-04). Run with `npm run db:test`.
BEGIN;

CREATE EXTENSION IF NOT EXISTS pgtap WITH SCHEMA extensions;

SELECT plan(22);

-- Otto organizes, Gwen is another member, and Sue is suspended.
INSERT INTO auth.users
  (id, email, raw_user_meta_data)
VALUES
  (
    'c0000000-0000-4000-8000-000000000041',
    'otto.organizer@byui.edu',
    '{"full_name": "Otto Organizer"}'
  ),
  ('c0000000-0000-4000-8000-000000000042', 'gwen.going@byui.edu', '{"full_name": "Gwen Going"}'),
  (
    'c0000000-0000-4000-8000-000000000043',
    'sue.suspended@byui.edu',
    '{"full_name": "Sue Suspended"}'
  );

UPDATE public.profiles
SET
  guidelines_version = 1,
  guidelines_accepted_at = now(),
  status = CASE id
    WHEN 'c0000000-0000-4000-8000-000000000043' THEN 'suspended'
    ELSE 'active'
  END
WHERE
  id IN
    (
      'c0000000-0000-4000-8000-000000000041',
      'c0000000-0000-4000-8000-000000000042',
      'c0000000-0000-4000-8000-000000000043'
    );

-- Upcoming, in a category that's no longer offered, started an hour ago, and hidden.
INSERT INTO public.activities
  (id, organizer_id, category_id, title, starts_at, location_name, hidden_at)
VALUES
  (
    'f0000000-0000-4000-8000-000000000041',
    'c0000000-0000-4000-8000-000000000041',
    'games',
    'Board game night',
    now() + INTERVAL '1 day',
    'Here',
    NULL
  ),
  (
    'f0000000-0000-4000-8000-000000000042',
    'c0000000-0000-4000-8000-000000000041',
    'online',
    'Online chess',
    now() + INTERVAL '1 day',
    'Here',
    NULL
  ),
  (
    'f0000000-0000-4000-8000-000000000043',
    'c0000000-0000-4000-8000-000000000041',
    'outdoors',
    'Sunrise hike',
    now() - INTERVAL '1 hour',
    'R Mountain',
    NULL
  ),
  (
    'f0000000-0000-4000-8000-000000000044',
    'c0000000-0000-4000-8000-000000000041',
    'games',
    'Hidden game',
    now() + INTERVAL '1 day',
    'Here',
    now()
  );

SET LOCAL ROLE authenticated;

SELECT set_config(
  'request.jwt.claims',
  '{"sub": "c0000000-0000-4000-8000-000000000041", "email": "otto.organizer@byui.edu"}',
  TRUE
);

SELECT lives_ok(
  $$select public.update_activity(
    'f0000000-0000-4000-8000-000000000041',
    jsonb_build_object(
      'title', ' Board game marathon ',
      'category_id', 'food',
      'starts_at', date_trunc('minute', now()) + interval '2 days',
      'ends_at', date_trunc('minute', now()) + interval '2 days 3 hours',
      'location_name', ' The library ',
      'description', ' ',
      'cost_note', ' $5 for pizza '
    ),
    1
  )$$,
  'the organizer changes every field'
);

SELECT results_eq(
  $$select title, category_id, starts_at, ends_at, location_name, description, cost_note, version
  from public.activities where id = 'f0000000-0000-4000-8000-000000000041'$$,
  $$values (
    'Board game marathon'::text,
    'food'::text,
    date_trunc('minute', now()) + interval '2 days',
    date_trunc('minute', now()) + interval '2 days 3 hours',
    'The library'::text,
    null::text,
    '$5 for pizza'::text,
    2
  )$$,
  'it stores trimmed text, NULL for blank optional text, and the next version'
);

SELECT ok(
  (
    SELECT time_or_place_changed_at = now()
    FROM public.activities
    WHERE id = 'f0000000-0000-4000-8000-000000000041'
  ),
  'it records that the time or place changed'
);

RESET role;

UPDATE public.activities
SET time_or_place_changed_at = NULL
WHERE id = 'f0000000-0000-4000-8000-000000000041';

SET LOCAL ROLE authenticated;

SELECT public.update_activity(
  'f0000000-0000-4000-8000-000000000041',
  '{"title": "Board game night", "description": "Bring a game", "cost_note": null}',
  2
);

SELECT results_eq(
  $$select description, cost_note, time_or_place_changed_at
  from public.activities where id = 'f0000000-0000-4000-8000-000000000041'$$,
  $$values ('Bring a game'::text, null::text, null::timestamptz)$$,
  'a null clears an optional field, and the label waits for a time or place change'
);

-- What it refuses
SELECT throws_ok(
  $$select public.update_activity('f0000000-0000-4000-8000-000000000041', '{"title": "Old"}', 2)$$,
  '40001',
  'STALE_EDIT',
  'a save from an older version fails'
);

SELECT throws_ok(
  $$select public.update_activity('f0000000-0000-4000-8000-000000000041', '{"going_count": 99}', 3)$$,
  '22023',
  'INVALID_FIELD',
  'only the form''s fields can change'
);

SELECT throws_ok(
  $$select public.update_activity(
    'f0000000-0000-4000-8000-000000000041',
    jsonb_build_object('starts_at', now() - interval '1 minute'),
    3
  )$$,
  '22023',
  'START_IN_PAST',
  'the start must be in the future'
);

SELECT throws_ok(
  $$select public.update_activity(
    'f0000000-0000-4000-8000-000000000041',
    jsonb_build_object('starts_at', now() + interval '12 months 1 day'),
    3
  )$$,
  '22023',
  'START_TOO_FAR',
  'the start must be no more than 12 months ahead'
);

SELECT throws_ok(
  $$select public.update_activity(
    'f0000000-0000-4000-8000-000000000041',
    jsonb_build_object('ends_at', now() + interval '1 hour'),
    3
  )$$,
  '22023',
  'END_BEFORE_START',
  'the end must be after the start'
);

SELECT throws_ok(
  $$select public.update_activity(
    'f0000000-0000-4000-8000-000000000041', '{"category_id": "online"}', 3
  )$$,
  '22023',
  'INVALID_CATEGORY',
  'a new category must be active'
);

SELECT lives_ok(
  $$select public.update_activity(
    'f0000000-0000-4000-8000-000000000042', '{"title": "Online chess club"}', 1
  )$$,
  'an activity keeps a category that''s no longer offered'
);

SELECT lives_ok(
  $$select public.update_activity('f0000000-0000-4000-8000-000000000044', '{"title": "Fixed"}', 1)$$,
  'the organizer edits a hidden activity, for a moderator to unhide'
);

-- Once it has started
SELECT lives_ok(
  $$select public.update_activity(
    'f0000000-0000-4000-8000-000000000043', '{"description": "Thanks for coming!"}', 1
  )$$,
  'the organizer changes the description of an activity that has started'
);

SELECT extensions.is(
  (SELECT description FROM public.activities WHERE id = 'f0000000-0000-4000-8000-000000000043'),
  'Thanks for coming!',
  'and it''s stored'
);

SELECT throws_ok(
  $$select public.update_activity(
    'f0000000-0000-4000-8000-000000000043', '{"location_name": "Somewhere else"}', 2
  )$$,
  '22023',
  'ACTIVITY_STARTED',
  'nothing else can change once it has started'
);

SELECT lives_ok(
  $$select public.update_activity(
    'f0000000-0000-4000-8000-000000000043',
    jsonb_build_object(
      'title', 'Sunrise hike',
      'category_id', 'outdoors',
      'starts_at', a.starts_at,
      'ends_at', null,
      'location_name', 'R Mountain',
      'description', 'See you next time',
      'cost_note', null
    ),
    2
  ) from public.activities as a where a.id = 'f0000000-0000-4000-8000-000000000043'$$,
  'a form opened before the start still saves, when only the description changed'
);

-- Who can't
SELECT set_config(
  'request.jwt.claims',
  '{"sub": "c0000000-0000-4000-8000-000000000042", "email": "gwen.going@byui.edu"}',
  TRUE
);

SELECT throws_ok(
  $$select public.update_activity('f0000000-0000-4000-8000-000000000041', '{"title": "Mine"}', 3)$$,
  '42501',
  'NOT_ORGANIZER',
  'another member can''t edit it'
);

SELECT throws_ok(
  $$select public.update_activity('f0000000-0000-4000-8000-000000000049', '{"title": "Mine"}', 1)$$,
  '42501',
  'NOT_ORGANIZER',
  'an activity that doesn''t exist fails the same way'
);

SELECT throws_ok(
  $$update public.activities set title = 'Mine' where id = 'f0000000-0000-4000-8000-000000000041'$$,
  '42501',
  NULL,
  'members can''t write activities directly'
);

SELECT set_config(
  'request.jwt.claims',
  '{"sub": "c0000000-0000-4000-8000-000000000043", "email": "sue.suspended@byui.edu"}',
  TRUE
);

SELECT throws_ok(
  $$select public.update_activity('f0000000-0000-4000-8000-000000000041', '{"title": "Mine"}', 3)$$,
  '42501',
  'NOT_ACTIVE',
  'a suspended member can''t edit'
);

RESET role;

SELECT ok(
  NOT has_function_privilege('anon', 'public.update_activity(uuid, jsonb, integer)', 'execute'),
  'signed-out visitors can''t edit'
);

SELECT ok(
  has_function_privilege(
    'authenticated',
    'public.update_activity(uuid, jsonb, integer)',
    'execute'
  ),
  'signed-in users can call update_activity'
);

SELECT *
FROM finish();

ROLLBACK;
