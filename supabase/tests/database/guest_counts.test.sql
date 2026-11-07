-- Keeping guest_total right when accounts go or move (RSVP-06). Run with `npm run db:test`.
BEGIN;

CREATE EXTENSION IF NOT EXISTS pgtap WITH SCHEMA extensions;

SELECT plan(4);

-- Ola organizes a picnic. Max is going with 2 guests, and leaves. Old Ann is going with 1 guest,
-- and moves to New Ann, who has already said going with 3.
INSERT INTO auth.users
  (id, email, raw_user_meta_data)
SELECT
  ('c0000000-0000-4000-8000-00000000026' || n)::uuid,
  name || '@byui.edu',
  jsonb_build_object('full_name', name)
FROM (
  VALUES
    (1, 'ola'),
    (2, 'max'),
    (3, 'oldann'),
    (4, 'newann')
) AS v (n, name);

UPDATE public.profiles
SET
  guidelines_version = 1,
  guidelines_accepted_at = now()
WHERE id::text LIKE 'c0000000-0000-4000-8000-00000000026_';

INSERT INTO public.activities
  (id, organizer_id, category_id, title, starts_at, location_name, going_count, guest_total)
VALUES
  (
    'f0000000-0000-4000-8000-000000000261',
    'c0000000-0000-4000-8000-000000000261',
    'food',
    'Picnic',
    now() + INTERVAL '1 day',
    'Park',
    4,
    6
  );

INSERT INTO public.rsvps
  (activity_id, user_id, status, guest_count)
SELECT
  'f0000000-0000-4000-8000-000000000261',
  ('c0000000-0000-4000-8000-00000000026' || member)::uuid,
  'going',
  guests
FROM (
  VALUES
    ('1', 0),
    ('2', 2),
    ('3', 1),
    ('4', 3)
) AS v (member, guests);

SET LOCAL ROLE authenticated;

SELECT set_config(
  'request.jwt.claims',
  '{"sub": "c0000000-0000-4000-8000-000000000262", "email": "max@byui.edu"}',
  TRUE
);

SELECT lives_ok(
  'select public.delete_my_account()',
  'a member bringing guests deletes their account'
);

RESET ROLE;

SELECT results_eq(
  $$select going_count, guest_total from public.activities
  where id = 'f0000000-0000-4000-8000-000000000261'$$,
  $$values (3, 4)$$,
  'and their guests go with them'
);

SELECT lives_ok(
  $$select private.transfer_account(
    'c0000000-0000-4000-8000-000000000263',
    'c0000000-0000-4000-8000-000000000264',
    'New Google account'
  )$$,
  'an admin moves a member to their new account'
);

SELECT results_eq(
  $$select going_count, guest_total from public.activities
  where id = 'f0000000-0000-4000-8000-000000000261'$$,
  $$values (2, 3)$$,
  'which drops the RSVP and guests the new account had already answered'
);

SELECT *
FROM finish();

ROLLBACK;
