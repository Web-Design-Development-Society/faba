-- Downloading my data (PRIV-01). Run with `npm run db:test`.
BEGIN;

CREATE EXTENSION IF NOT EXISTS pgtap WITH SCHEMA extensions;

SELECT plan(4);

INSERT INTO auth.users
  (id, email, raw_user_meta_data)
VALUES
  ('c0000000-0000-4000-8000-000000001801', 'ada@byui.edu', '{"full_name": "Ada Export"}'),
  ('c0000000-0000-4000-8000-000000001802', 'ben@byui.edu', '{"full_name": "Ben Export"}');

UPDATE public.profiles
SET
  guidelines_version = 1,
  guidelines_accepted_at = now()
WHERE id BETWEEN 'c0000000-0000-4000-8000-000000001801' AND 'c0000000-0000-4000-8000-000000001802';

SET LOCAL ROLE authenticated;

SELECT set_config(
  'request.jwt.claims',
  '{"sub": "c0000000-0000-4000-8000-000000001801", "email": "ada@byui.edu"}',
  TRUE
);

SELECT results_eq(
  $$select (public.export_my_data() -> 'profile' ->> 'id')::uuid$$,
  $$values ('c0000000-0000-4000-8000-000000001801'::uuid)$$,
  'the export has the signed-in member''s profile'
);

SELECT results_eq(
  $$select jsonb_array_length(public.export_my_data() -> 'rsvps')$$,
  $$values (0)$$,
  'the export has the member''s own lists'
);

SELECT lives_ok($$select public.export_my_data()$$, 'a second export is allowed');

SELECT throws_ok(
  $$select public.export_my_data()$$,
  '53400',
  'EXPORT_QUOTA_EXCEEDED',
  'exports are limited to three in 24 hours'
);

ROLLBACK;
