-- Co-organizers (ACT-10). Run with `npm run db:test`.
BEGIN;

CREATE EXTENSION IF NOT EXISTS pgtap WITH SCHEMA extensions;

SELECT plan(11);

-- Tia organizes. Max, Ana, Ben and Cy are members. Dee is suspended.
INSERT INTO auth.users
  (id, email, raw_user_meta_data)
VALUES
  ('c0000000-0000-4000-8000-000000000301', 'tia@byui.edu', '{"full_name": "Tia Host"}'),
  ('c0000000-0000-4000-8000-000000000302', 'max@byui.edu', '{"full_name": "Max Member"}'),
  ('c0000000-0000-4000-8000-000000000303', 'ana@byui.edu', '{"full_name": "Ana Member"}'),
  ('c0000000-0000-4000-8000-000000000304', 'ben@byui.edu', '{"full_name": "Ben Member"}'),
  ('c0000000-0000-4000-8000-000000000305', 'cy@byui.edu', '{"full_name": "Cy Member"}'),
  ('c0000000-0000-4000-8000-000000000306', 'dee@byui.edu', '{"full_name": "Dee Member"}');

UPDATE public.profiles
SET
  guidelines_version = 1,
  guidelines_accepted_at = now()
WHERE id BETWEEN 'c0000000-0000-4000-8000-000000000301' AND 'c0000000-0000-4000-8000-000000000306';

UPDATE public.profiles
SET status = 'suspended'
WHERE id = 'c0000000-0000-4000-8000-000000000306';

INSERT INTO public.activities
  (id, organizer_id, category_id, title, starts_at, location_name)
VALUES
  (
    'f0000000-0000-4000-8000-000000000301',
    'c0000000-0000-4000-8000-000000000301',
    'food',
    'Picnic',
    now() + INTERVAL '1 day',
    'Park'
  );

-- Max becomes a co-organizer as the organizer, the way the function is used.
SET LOCAL ROLE authenticated;

SELECT set_config(
  'request.jwt.claims',
  '{"sub": "c0000000-0000-4000-8000-000000000301", "email": "tia@byui.edu"}',
  TRUE
);

SELECT lives_ok(
  $$select public.add_co_organizer('f0000000-0000-4000-8000-000000000301', 'c0000000-0000-4000-8000-000000000302')$$,
  'the organizer adds a co-organizer'
);

SELECT results_eq(
  $$select count(*)::int from public.activity_co_organizers where activity_id = 'f0000000-0000-4000-8000-000000000301'$$,
  $$values (1)$$,
  'the co-organizer is recorded'
);

SELECT lives_ok(
  $$select public.add_co_organizer('f0000000-0000-4000-8000-000000000301', 'c0000000-0000-4000-8000-000000000302')$$,
  'adding the same co-organizer again changes nothing'
);

SELECT lives_ok(
  $$select public.add_co_organizer('f0000000-0000-4000-8000-000000000301', 'c0000000-0000-4000-8000-000000000303')$$,
  'a second co-organizer is added'
);

SELECT lives_ok(
  $$select public.add_co_organizer('f0000000-0000-4000-8000-000000000301', 'c0000000-0000-4000-8000-000000000304')$$,
  'a third co-organizer is added'
);

SELECT throws_ok(
  $$select public.add_co_organizer('f0000000-0000-4000-8000-000000000301', 'c0000000-0000-4000-8000-000000000305')$$,
  '22023',
  'TOO_MANY_CO_ORGANIZERS',
  'a fourth co-organizer is refused'
);

SELECT throws_ok(
  $$select public.add_co_organizer('f0000000-0000-4000-8000-000000000301', 'c0000000-0000-4000-8000-000000000306')$$,
  'P0002',
  'MEMBER_NOT_FOUND',
  'a suspended member can''t be added'
);

-- Max, a co-organizer, can edit the activity as the organizer can.
SELECT set_config(
  'request.jwt.claims',
  '{"sub": "c0000000-0000-4000-8000-000000000302", "email": "max@byui.edu"}',
  TRUE
);

SELECT results_eq(
  $$select private.is_activity_organizer('f0000000-0000-4000-8000-000000000301')$$,
  $$values (true)$$,
  'a co-organizer passes the organizer check'
);

SELECT lives_ok(
  $$select public.set_activity_tags('f0000000-0000-4000-8000-000000000301', array['free'])$$,
  'a co-organizer can set the tags'
);

-- Max can't add Cy either, because the limit of 3 is already reached.
SELECT throws_ok(
  $$select public.add_co_organizer('f0000000-0000-4000-8000-000000000301', 'c0000000-0000-4000-8000-000000000305')$$,
  '22023',
  'TOO_MANY_CO_ORGANIZERS',
  'a co-organizer can''t go past the limit either'
);

-- Cy is a member but not an organizer, so Cy can't edit.
SELECT set_config(
  'request.jwt.claims',
  '{"sub": "c0000000-0000-4000-8000-000000000305", "email": "cy@byui.edu"}',
  TRUE
);

SELECT throws_ok(
  $$select public.set_activity_tags('f0000000-0000-4000-8000-000000000301', array['free'])$$,
  '42501',
  'NOT_ORGANIZER',
  'a member who is neither organizer nor co-organizer can''t edit'
);

SELECT * FROM finish();
ROLLBACK;
