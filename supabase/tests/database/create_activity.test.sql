-- Posting an activity, and who reads RSVPs (ACT-03). Run with `npm run db:test`.
BEGIN;

CREATE EXTENSION IF NOT EXISTS pgtap WITH SCHEMA extensions;

SELECT plan(21);

-- A member who has accepted the guidelines and hasn't posted anything
INSERT INTO auth.users
  (id, email, raw_user_meta_data)
VALUES
  ('c0000000-0000-4000-8000-000000000001', 'pat.poster@byui.edu', '{"full_name": "Pat Poster"}');

UPDATE public.profiles
SET
  guidelines_version = 1,
  guidelines_accepted_at = now()
WHERE id = 'c0000000-0000-4000-8000-000000000001';

SET LOCAL ROLE authenticated;

SELECT set_config(
  'request.jwt.claims',
  '{"sub": "c0000000-0000-4000-8000-000000000001", "email": "pat.poster@byui.edu"}',
  TRUE
);

SELECT lives_ok(
  $$select public.create_activity(
    '  Sunrise hike  ',
    'outdoors',
    now() + interval '1 day',
    ' R Mountain trailhead ',
    '',
    now() + interval '1 day 2 hours',
    ' ',
    'd0000000-0000-4000-8000-000000000001'
  )$$,
  'a member posts an activity'
);

SELECT results_eq(
  $$select title, location_name, description, cost_note, timezone, going_count, organizer_id
  from public.activities where idempotency_key = 'd0000000-0000-4000-8000-000000000001'$$,
  $$values (
    'Sunrise hike'::text,
    'R Mountain trailhead'::text,
    null::text,
    null::text,
    'America/Denver'::text,
    1,
    'c0000000-0000-4000-8000-000000000001'::uuid
  )$$,
  'it stores trimmed text, NULL for blank optional text, Rexburg time, and the organizer going'
);

SELECT results_eq(
  $$select r.status from public.rsvps as r join public.activities as a on a.id = r.activity_id
  where a.idempotency_key = 'd0000000-0000-4000-8000-000000000001' and r.user_id = auth.uid()$$,
  $$values ('going'::text)$$,
  'the organizer has a going RSVP'
);

SELECT extensions.is(
  public.create_activity(
    'Another title',
    'games',
    now() + INTERVAL '2 days',
    'Somewhere else',
    idempotency_key => 'd0000000-0000-4000-8000-000000000001'
  ),
  (SELECT id FROM public.activities WHERE idempotency_key = 'd0000000-0000-4000-8000-000000000001'),
  'a repeated idempotency key returns the activity it already made'
);

SELECT extensions.is(
  (SELECT count(*) FROM public.activities WHERE organizer_id = auth.uid()),
  1::BIGINT,
  'and posts nothing new'
);

-- What it refuses
SELECT throws_ok(
  $$select public.create_activity('Too late', 'games', now() - interval '1 minute', 'Here')$$,
  '22023',
  'START_IN_PAST',
  'the start must be in the future'
);

SELECT throws_ok(
  $$select public.create_activity('Too far', 'games', now() + interval '12 months 1 day', 'Here')$$,
  '22023',
  'START_TOO_FAR',
  'the start must be no more than 12 months ahead'
);

SELECT throws_ok(
  $$select public.create_activity(
    'Backwards', 'games', now() + interval '1 day', 'Here', ends_at => now() + interval '1 day'
  )$$,
  '22023',
  'END_BEFORE_START',
  'the end must be after the start'
);

SELECT throws_ok(
  $$select public.create_activity('A call', 'online', now() + interval '1 day', 'Here')$$,
  '22023',
  'INVALID_CATEGORY',
  'the category must be active'
);

SELECT throws_ok(
  $$select public.create_activity(' Hi ', 'games', now() + interval '1 day', 'Here')$$,
  '23514',
  NULL,
  'a title shorter than 3 characters fails'
);

-- The daily limit: 9 more posted just now make 10
RESET role;

INSERT INTO public.activities
  (organizer_id, category_id, title, starts_at, location_name)
SELECT
  'c0000000-0000-4000-8000-000000000001',
  'games',
  'Game night ' || n,
  now() + INTERVAL '3 days',
  'Here'
FROM generate_series(1, 9) AS n;

SET LOCAL ROLE authenticated;

SELECT throws_ok(
  $$select public.create_activity('One too many', 'games', now() + interval '1 day', 'Here')$$,
  'P0001',
  'QUOTA_EXCEEDED',
  'an 11th activity in 24 hours fails'
);

SELECT extensions.is(
  public.create_activity(
    'Sunrise hike',
    'outdoors',
    now() + INTERVAL '1 day',
    'Here',
    idempotency_key => 'd0000000-0000-4000-8000-000000000001'
  ),
  (SELECT id FROM public.activities WHERE idempotency_key = 'd0000000-0000-4000-8000-000000000001'),
  'a repeated key still returns its activity at the limit'
);

RESET role;

UPDATE public.activities
SET created_at = now() - INTERVAL '25 hours'
WHERE title LIKE 'Game night %';

SET LOCAL ROLE authenticated;

SELECT lives_ok(
  $$select public.create_activity('Back again', 'games', now() + interval '1 day', 'Here')$$,
  'activities posted more than 24 hours ago don''t count'
);

-- Who can't post
SELECT set_config(
  'request.jwt.claims',
  '{"sub": "00000000-0000-4000-8000-000000000005", "email": "suspended.test@byui.edu"}',
  TRUE
);

SELECT throws_ok(
  $$select public.create_activity('Sneaky', 'games', now() + interval '1 day', 'Here')$$,
  '42501',
  'NOT_ACTIVE',
  'a suspended member can''t post'
);

SELECT set_config(
  'request.jwt.claims',
  '{"sub": "c0000000-0000-4000-8000-000000000001", "email": "pat.poster@gmail.com"}',
  TRUE
);

SELECT throws_ok(
  $$select public.create_activity('Sneaky', 'games', now() + interval '1 day', 'Here')$$,
  '42501',
  'NOT_ACTIVE',
  'a session whose email isn''t byui.edu can''t post'
);

-- Who reads RSVPs. Maya Member isn't going to Pat's hike.
RESET role;

INSERT INTO public.rsvps
  (activity_id, user_id, status)
SELECT id, '00000000-0000-4000-8000-000000000001', 'not_going'
FROM public.activities
WHERE idempotency_key = 'd0000000-0000-4000-8000-000000000001';

SET LOCAL ROLE authenticated;

SELECT set_config(
  'request.jwt.claims',
  '{"sub": "00000000-0000-4000-8000-000000000001", "email": "member.test@byui.edu"}',
  TRUE
);

SELECT results_eq(
  $$select r.user_id, r.status from public.rsvps as r join public.activities as a
  on a.id = r.activity_id where a.idempotency_key = 'd0000000-0000-4000-8000-000000000001'
  order by r.status$$,
  $$values
    ('c0000000-0000-4000-8000-000000000001'::uuid, 'going'::text),
    ('00000000-0000-4000-8000-000000000001'::uuid, 'not_going'::text)$$,
  'members read who''s going and their own RSVP'
);

SELECT throws_ok(
  $$insert into public.rsvps (activity_id, user_id, status)
  select id, auth.uid(), 'going' from public.activities limit 1$$,
  '42501',
  NULL,
  'members can''t write RSVPs directly'
);

SELECT set_config(
  'request.jwt.claims',
  '{"sub": "00000000-0000-4000-8000-000000000002", "email": "organizer.test@byui.edu"}',
  TRUE
);

SELECT is_empty(
  $$select from public.rsvps where status = 'not_going'
  and user_id = '00000000-0000-4000-8000-000000000001'$$,
  'other members don''t read who isn''t going'
);

SELECT set_config(
  'request.jwt.claims',
  '{"sub": "c0000000-0000-4000-8000-000000000001", "email": "pat.poster@byui.edu"}',
  TRUE
);

-- Not even the organizer (RSVP-02).
SELECT is_empty(
  $$select from public.rsvps where status = 'not_going'
  and user_id = '00000000-0000-4000-8000-000000000001'$$,
  'organizers don''t read who isn''t going either'
);

RESET role;

SELECT ok(
  NOT has_function_privilege(
    'anon',
    'public.create_activity(text, text, timestamptz, text, text, timestamptz, text, uuid)',
    'execute'
  ),
  'signed-out visitors can''t post'
);

SELECT ok(
  has_function_privilege(
    'authenticated',
    'public.create_activity(text, text, timestamptz, text, text, timestamptz, text, uuid)',
    'execute'
  ),
  'signed-in users can call create_activity'
);

SELECT *
FROM finish();

ROLLBACK;
