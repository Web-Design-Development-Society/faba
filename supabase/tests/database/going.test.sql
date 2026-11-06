-- Who's going (RSVP-03, FR-RSVP-4). Only active members read who's going, and suspended members
-- aren't in it. Run with `npm run db:test`.
BEGIN;

CREATE EXTENSION IF NOT EXISTS pgtap WITH SCHEMA extensions;

SELECT plan(3);

-- Otto organizes, and Gwen and Sue are going. Sue is suspended.
INSERT INTO auth.users
  (id, email, raw_user_meta_data)
VALUES
  (
    'c0000000-0000-4000-8000-000000000031',
    'otto.organizer@byui.edu',
    '{"full_name": "Otto Organizer"}'
  ),
  ('c0000000-0000-4000-8000-000000000032', 'gwen.going@byui.edu', '{"full_name": "Gwen Going"}'),
  (
    'c0000000-0000-4000-8000-000000000033',
    'sue.suspended@byui.edu',
    '{"full_name": "Sue Suspended"}'
  );

UPDATE public.profiles
SET
  guidelines_version = 1,
  guidelines_accepted_at = now(),
  status = CASE id
    WHEN 'c0000000-0000-4000-8000-000000000033' THEN 'suspended'
    ELSE 'active'
  END
WHERE
  id IN (
    'c0000000-0000-4000-8000-000000000031',
    'c0000000-0000-4000-8000-000000000032',
    'c0000000-0000-4000-8000-000000000033'
  );

INSERT INTO public.activities
  (id, organizer_id, category_id, title, starts_at, location_name, going_count)
VALUES
  (
    'f0000000-0000-4000-8000-000000000031',
    'c0000000-0000-4000-8000-000000000031',
    'games',
    'Board game night',
    now() + INTERVAL '1 day',
    'Here',
    3
  );

INSERT INTO public.rsvps
  (activity_id, user_id, status)
VALUES
  ('f0000000-0000-4000-8000-000000000031', 'c0000000-0000-4000-8000-000000000031', 'going'),
  ('f0000000-0000-4000-8000-000000000031', 'c0000000-0000-4000-8000-000000000032', 'going'),
  ('f0000000-0000-4000-8000-000000000031', 'c0000000-0000-4000-8000-000000000033', 'going');

SET LOCAL ROLE anon;

SELECT throws_ok(
  'select from public.rsvps',
  '42501',
  NULL,
  'signed-out visitors can''t read who''s going'
);

SET LOCAL ROLE authenticated;

SELECT set_config(
  'request.jwt.claims',
  '{"sub": "c0000000-0000-4000-8000-000000000032", "email": "gwen.going@byui.edu"}',
  TRUE
);

-- As the activity's page reads it.
SELECT results_eq(
  $$select p.display_name from public.rsvps as r join public.profiles as p on p.id = r.user_id
  where r.activity_id = 'f0000000-0000-4000-8000-000000000031' and r.status = 'going'
  order by p.display_name$$,
  $$values ('Gwen Going'::text), ('Otto Organizer'::text)$$,
  'members read who''s going, without suspended members'
);

SELECT set_config(
  'request.jwt.claims',
  '{"sub": "c0000000-0000-4000-8000-000000000033", "email": "sue.suspended@byui.edu"}',
  TRUE
);

SELECT is_empty(
  'select from public.rsvps',
  'a suspended member reads no RSVPs, not even their own'
);

SELECT * FROM finish();

ROLLBACK;
