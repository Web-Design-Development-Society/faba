-- Attendance history is private (FR-PROF-5, FR-HIST-3). Members read who's going only until an
-- activity is over, and only their own RSVP after that. Run with `npm run db:test`.
BEGIN;

CREATE EXTENSION IF NOT EXISTS pgtap WITH SCHEMA extensions;

SELECT plan(5);

-- Otto organizes five activities. Tomorrow's, one that started 2 hours ago, and an all-day one
-- that started 5 hours ago aren't over. One that ended an hour ago and one 2 days ago are. Gwen
-- and Max go to all five, and Mia is maybe for tomorrow's and the one 2 days ago.
INSERT INTO auth.users
  (id, email, raw_user_meta_data)
SELECT
  ('c0000000-0000-4000-8000-00000000030' || n)::uuid,
  name || '@byui.edu',
  jsonb_build_object('full_name', name)
FROM (
  VALUES
    (1, 'otto'),
    (2, 'gwen'),
    (3, 'max'),
    (4, 'mia')
) AS v (n, name);

UPDATE public.profiles
SET
  guidelines_version = 1,
  guidelines_accepted_at = now()
WHERE id::text LIKE 'c0000000-0000-4000-8000-00000000030_';

INSERT INTO public.activities
  (
    id,
    organizer_id,
    category_id,
    title,
    starts_at,
    ends_at,
    location_name,
    going_count,
    maybe_count
  )
SELECT
  ('f0000000-0000-4000-8000-00000000030' || n)::uuid,
  'c0000000-0000-4000-8000-000000000301',
  'outdoors',
  title,
  starts_at,
  ends_at,
  'R Mountain trailhead',
  3,
  maybe_count
FROM (
  VALUES
    (1, 'Tomorrow''s hike', now() + INTERVAL '1 day', NULL::timestamptz, 1),
    (2, 'Today''s hike', now() - INTERVAL '2 hours', NULL, 0),
    (3, 'All-day climb', now() - INTERVAL '5 hours', now() + INTERVAL '1 hour', 0),
    (4, 'Last week''s hike', now() - INTERVAL '2 days', NULL, 1),
    (5, 'Short walk', now() - INTERVAL '2 hours', now() - INTERVAL '1 hour', 0)
) AS v (n, title, starts_at, ends_at, maybe_count);

INSERT INTO public.rsvps
  (activity_id, user_id, status)
SELECT
  ('f0000000-0000-4000-8000-00000000030' || a)::uuid,
  ('c0000000-0000-4000-8000-00000000030' || u)::uuid,
  CASE u
    WHEN 4 THEN 'maybe'
    ELSE 'going'
  END
FROM
  generate_series(1, 5) AS a,
  generate_series(1, 4) AS u
WHERE u < 4 OR a IN (1, 4);

SET LOCAL ROLE authenticated;

SELECT set_config(
  'request.jwt.claims',
  '{"sub": "c0000000-0000-4000-8000-000000000302", "email": "gwen@byui.edu"}',
  TRUE
);

SELECT results_eq(
  $$select activity_id from public.rsvps
  where user_id = 'c0000000-0000-4000-8000-000000000303' order by activity_id$$,
  $$values ('f0000000-0000-4000-8000-000000000301'::uuid),
    ('f0000000-0000-4000-8000-000000000302'::uuid),
    ('f0000000-0000-4000-8000-000000000303'::uuid)$$,
  'members can''t list where a colleague has been, only what they''re going to'
);

SELECT is_empty(
  $$select from public.rsvps where activity_id = 'f0000000-0000-4000-8000-000000000304'
  and user_id != 'c0000000-0000-4000-8000-000000000302'$$,
  'members don''t read who went to a past activity'
);

SELECT results_eq(
  $$select status from public.rsvps where activity_id = 'f0000000-0000-4000-8000-000000000304'$$,
  $$values ('going'::text)$$,
  'members still read their own RSVP to a past activity'
);

SELECT set_config(
  'request.jwt.claims',
  '{"sub": "c0000000-0000-4000-8000-000000000301", "email": "otto@byui.edu"}',
  TRUE
);

SELECT is_empty(
  $$select from public.rsvps where activity_id = 'f0000000-0000-4000-8000-000000000304'
  and user_id != 'c0000000-0000-4000-8000-000000000301'$$,
  'organizers don''t read who went to, or was maybe for, their past activity'
);

SELECT results_eq(
  $$select user_id from public.rsvps
  where activity_id = 'f0000000-0000-4000-8000-000000000301' and status = 'maybe'$$,
  $$values ('c0000000-0000-4000-8000-000000000304'::uuid)$$,
  'organizers still read who''s maybe for an upcoming activity'
);

SELECT * FROM finish();

ROLLBACK;
