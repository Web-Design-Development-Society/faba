-- Post again (ACT-07). Run with `npm run db:test`.
BEGIN;

CREATE EXTENSION IF NOT EXISTS pgtap WITH SCHEMA extensions;

SELECT plan(5);

-- Pam posts again, and Ike organizes something else.
INSERT INTO auth.users
  (id, email, raw_user_meta_data)
SELECT
  ('c0000000-0000-4000-8000-00000000039' || n)::uuid,
  name || '@byui.edu',
  jsonb_build_object('full_name', name)
FROM (
  VALUES
    (1, 'pam'),
    (2, 'ike')
) AS v (n, name);

UPDATE public.profiles
SET
  guidelines_version = 1,
  guidelines_accepted_at = now()
WHERE id::text LIKE 'c0000000-0000-4000-8000-00000000039_';

INSERT INTO public.activities
  (id, organizer_id, category_id, title, starts_at, location_name)
VALUES
  (
    'f0000000-0000-4000-8000-000000000391',
    'c0000000-0000-4000-8000-000000000391',
    'games',
    'Board game night',
    now() - INTERVAL '7 days',
    'Library'
  ),
  (
    'f0000000-0000-4000-8000-000000000392',
    'c0000000-0000-4000-8000-000000000392',
    'games',
    'Chess club',
    now() - INTERVAL '7 days',
    'Library'
  );

SET LOCAL ROLE authenticated;

SELECT set_config(
  'request.jwt.claims',
  '{"sub": "c0000000-0000-4000-8000-000000000391", "email": "pam@byui.edu"}',
  TRUE
);

-- Posts a copy of `original` next week, returning what it was copied from.
CREATE FUNCTION pg_temp.copy(original uuid)
RETURNS uuid
LANGUAGE plpgsql
AS $$
declare
  copy_id uuid := public.create_activity(
    title => 'Board game night',
    category_id => 'games',
    starts_at => now() + interval '7 days',
    location_name => 'Library',
    copied_from_id => original
  );
begin
  return (select a.copied_from_id from public.activities as a where a.id = copy_id);
end;
$$;

SELECT results_eq(
  $$select pg_temp.copy('f0000000-0000-4000-8000-000000000391')$$,
  $$values ('f0000000-0000-4000-8000-000000000391'::uuid)$$,
  'a copy of their own activity keeps where it came from'
);

SELECT results_eq(
  $$select pg_temp.copy('f0000000-0000-4000-8000-000000000392')$$,
  $$values (null::uuid)$$,
  'but not when it''s someone else''s'
);

SELECT results_eq(
  $$select pg_temp.copy('f0000000-0000-4000-8000-000000000399')$$,
  $$values (null::uuid)$$,
  'or one that doesn''t exist'
);

SELECT results_eq(
  $$select pg_temp.copy(null)$$,
  $$values (null::uuid)$$,
  'and a new activity has none'
);

RESET ROLE;

DELETE FROM public.activities
WHERE id = 'f0000000-0000-4000-8000-000000000391';

SELECT is_empty(
  $$
    select from public.activities
    where organizer_id = 'c0000000-0000-4000-8000-000000000391' and copied_from_id is not null
  $$,
  'deleting the original clears it'
);

SELECT *
FROM finish();

ROLLBACK;
