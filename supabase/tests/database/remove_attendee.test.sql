-- Managing the attendee list (RSVP-09). Run with `npm run db:test`.
BEGIN;

CREATE EXTENSION IF NOT EXISTS pgtap WITH SCHEMA extensions;

SELECT plan(11);

-- Tia organizes and Cy co-organizes. Max and Ana are going, Ben is on the waitlist, and Dee is a
-- member who isn't going.
INSERT INTO auth.users
  (id, email, raw_user_meta_data)
VALUES
  ('c0000000-0000-4000-8000-000000000401', 'tia@byui.edu', '{"full_name": "Tia Host"}'),
  ('c0000000-0000-4000-8000-000000000402', 'max@byui.edu', '{"full_name": "Max Going"}'),
  ('c0000000-0000-4000-8000-000000000403', 'ana@byui.edu', '{"full_name": "Ana Going"}'),
  ('c0000000-0000-4000-8000-000000000404', 'ben@byui.edu', '{"full_name": "Ben Waiting"}'),
  ('c0000000-0000-4000-8000-000000000405', 'cy@byui.edu', '{"full_name": "Cy Co"}'),
  ('c0000000-0000-4000-8000-000000000406', 'dee@byui.edu', '{"full_name": "Dee Member"}');

UPDATE public.profiles
SET
  guidelines_version = 1,
  guidelines_accepted_at = now()
WHERE id BETWEEN 'c0000000-0000-4000-8000-000000000401' AND 'c0000000-0000-4000-8000-000000000406';

INSERT INTO public.activities
  (
    id,
    organizer_id,
    category_id,
    title,
    starts_at,
    location_name,
    capacity,
    guests_allowed,
    max_guests_per_rsvp,
    going_count,
    guest_total
  )
VALUES
  (
    'f0000000-0000-4000-8000-000000000401',
    'c0000000-0000-4000-8000-000000000401',
    'food',
    'Picnic',
    now() + INTERVAL '2 days',
    'Park',
    3,
    TRUE,
    2,
    2,
    1
  );

INSERT INTO public.activity_co_organizers (activity_id, user_id)
VALUES ('f0000000-0000-4000-8000-000000000401', 'c0000000-0000-4000-8000-000000000405');

INSERT INTO public.rsvps (activity_id, user_id, status, guest_count, waitlisted_at)
VALUES
  (
    'f0000000-0000-4000-8000-000000000401',
    'c0000000-0000-4000-8000-000000000402',
    'going',
    1,
    NULL
  ),
  (
    'f0000000-0000-4000-8000-000000000401',
    'c0000000-0000-4000-8000-000000000403',
    'going',
    0,
    NULL
  ),
  (
    'f0000000-0000-4000-8000-000000000401',
    'c0000000-0000-4000-8000-000000000404',
    'waitlisted',
    0,
    now()
  );

SET LOCAL ROLE authenticated;

-- A member who isn't going can't remove anyone.
SELECT set_config(
  'request.jwt.claims',
  '{"sub": "c0000000-0000-4000-8000-000000000406", "email": "dee@byui.edu"}',
  TRUE
);

SELECT throws_ok(
  $$select public.remove_attendee('f0000000-0000-4000-8000-000000000401', 'c0000000-0000-4000-8000-000000000402')$$,
  '42501',
  'NOT_ATTENDEE_MANAGER',
  'a member who isn''t a manager can''t remove an attendee'
);

SELECT throws_ok(
  $$select public.attendee_names('f0000000-0000-4000-8000-000000000401')$$,
  '42501',
  'NOT_ATTENDEE_MANAGER',
  'a member who isn''t a manager can''t export the names'
);

-- The co-organizer removes Max. His spot and his guest are freed, and he gets a notification.
SELECT set_config(
  'request.jwt.claims',
  '{"sub": "c0000000-0000-4000-8000-000000000405", "email": "cy@byui.edu"}',
  TRUE
);

SELECT lives_ok(
  $$select public.remove_attendee('f0000000-0000-4000-8000-000000000401', 'c0000000-0000-4000-8000-000000000402')$$,
  'a co-organizer removes an attendee'
);

RESET ROLE;

SELECT results_eq(
  $$select going_count, guest_total from public.activities where id = 'f0000000-0000-4000-8000-000000000401'$$,
  $$values (2, 0)$$,
  'the counts drop the removed attendee and their guest'
);

-- Ben was waiting, and the freed spot goes to him.
SELECT results_eq(
  $$select status::text from public.rsvps where activity_id = 'f0000000-0000-4000-8000-000000000401' and user_id = 'c0000000-0000-4000-8000-000000000404'$$,
  $$values ('going'::text)$$,
  'the waitlist moves on into the freed spot'
);

SELECT results_eq(
  $$select type from public.notifications where recipient_id = 'c0000000-0000-4000-8000-000000000402'$$,
  $$values ('rsvp_removed'::text)$$,
  'the removed attendee is told'
);

-- Removing someone who isn't on the list again changes nothing.
SET LOCAL ROLE authenticated;

SELECT set_config(
  'request.jwt.claims',
  '{"sub": "c0000000-0000-4000-8000-000000000405", "email": "cy@byui.edu"}',
  TRUE
);

SELECT lives_ok(
  $$select public.remove_attendee('f0000000-0000-4000-8000-000000000401', 'c0000000-0000-4000-8000-000000000406')$$,
  'removing someone not going changes nothing'
);

SELECT throws_ok(
  $$select public.remove_attendee('f0000000-0000-4000-8000-000000000401', 'c0000000-0000-4000-8000-000000000401')$$,
  '22023',
  'CANNOT_REMOVE_ORGANIZER',
  'the organizer can''t be removed'
);

SELECT results_eq(
  $$select public.attendee_names('f0000000-0000-4000-8000-000000000401')$$,
  $$values ('Ana Going'::text), ('Ben Waiting'::text)$$,
  'the export lists names of those going, without guests'
);

-- The member who can manage attendees sees the controls. Dee can't.
SELECT results_eq(
  $$select public.manages_attendees('f0000000-0000-4000-8000-000000000401')$$,
  $$values (true)$$,
  'a co-organizer can manage the attendee list'
);

SELECT set_config(
  'request.jwt.claims',
  '{"sub": "c0000000-0000-4000-8000-000000000406", "email": "dee@byui.edu"}',
  TRUE
);

SELECT results_eq(
  $$select public.manages_attendees('f0000000-0000-4000-8000-000000000401')$$,
  $$values (false)$$,
  'a member who isn''t a manager doesn''t'
);

SELECT * FROM finish();
ROLLBACK;
