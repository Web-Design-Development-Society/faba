-- Welcoming guests (RSVP-06). Run with `npm run db:test`.
BEGIN;

CREATE EXTENSION IF NOT EXISTS pgtap WITH SCHEMA extensions;

SELECT plan(7);

INSERT INTO auth.users
  (id, email, raw_user_meta_data)
VALUES
  ('c0000000-0000-4000-8000-000000000251', 'gwen@byui.edu', '{"full_name": "Gwen Guests"}');

UPDATE public.profiles
SET
  guidelines_version = 1,
  guidelines_accepted_at = now()
WHERE id = 'c0000000-0000-4000-8000-000000000251';

-- Gwen's game is coming up, and her lunch has started.
INSERT INTO public.activities
  (id, organizer_id, category_id, title, starts_at, location_name, guests_allowed)
VALUES
  (
    'f0000000-0000-4000-8000-000000000251',
    'c0000000-0000-4000-8000-000000000251',
    'games',
    'Board games',
    now() + INTERVAL '1 day',
    'Here',
    FALSE
  ),
  (
    'f0000000-0000-4000-8000-000000000252',
    'c0000000-0000-4000-8000-000000000251',
    'food',
    'Lunch',
    now() - INTERVAL '1 hour',
    'Here',
    FALSE
  );

SET LOCAL ROLE authenticated;

SELECT set_config(
  'request.jwt.claims',
  '{"sub": "c0000000-0000-4000-8000-000000000251", "email": "gwen@byui.edu"}',
  TRUE
);

-- Posting
CREATE FUNCTION pg_temp.post(guests_allowed BOOLEAN, max_guests INTEGER)
RETURNS uuid
LANGUAGE sql
AS $$
  SELECT public.create_activity(
    title => 'Picnic',
    category_id => 'food',
    starts_at => now() + INTERVAL '2 days',
    location_name => 'Park',
    guests_allowed => guests_allowed,
    max_guests_per_rsvp => max_guests
  );
$$;

CREATE TEMPORARY TABLE posted AS
  SELECT pg_temp.post(TRUE, 3) AS welcoming, pg_temp.post(NULL, NULL) AS plain;

SELECT results_eq(
  $$select guests_allowed, max_guests_per_rsvp from public.activities
  where id = (select welcoming from posted)$$,
  $$values (true, 3)$$,
  'an organizer can welcome up to 3 guests each'
);

SELECT results_eq(
  $$select guests_allowed, max_guests_per_rsvp from public.activities
  where id = (select plain from posted)$$,
  $$values (false, 5)$$,
  'or not welcome guests'
);

SELECT throws_ok('select pg_temp.post(true, 6)', '22023', 'INVALID_GUESTS', 'but not more than 5');

-- Editing
CREATE FUNCTION pg_temp.edit(activity text, patch jsonb)
RETURNS void
LANGUAGE sql
AS $$
  SELECT public.update_activity(
    ('f0000000-0000-4000-8000-00000000025' || activity)::uuid,
    patch,
    (
      SELECT version
      FROM public.activities
      WHERE id = ('f0000000-0000-4000-8000-00000000025' || activity)::uuid
    )
  );
$$;

SELECT lives_ok(
  $$select pg_temp.edit('1', '{"guests_allowed": true, "max_guests_per_rsvp": 2}')$$,
  'an organizer can welcome guests later'
);

SELECT results_eq(
  $$select guests_allowed, max_guests_per_rsvp from public.activities
  where id = 'f0000000-0000-4000-8000-000000000251'$$,
  $$values (true, 2)$$,
  'which saves'
);

SELECT throws_ok(
  $$select pg_temp.edit('1', '{"max_guests_per_rsvp": 0}')$$,
  '22023',
  'INVALID_GUESTS',
  'with at least 1 each'
);

SELECT throws_ok(
  $$select pg_temp.edit('2', '{"guests_allowed": true}')$$,
  '22023',
  'ACTIVITY_STARTED',
  'until it starts'
);

SELECT *
FROM finish();

ROLLBACK;
