-- Database checks that hold for the whole schema (design document section 12.9), plus the
-- profile trigger and the category list. Run with `npm run db:test`.
BEGIN;

CREATE EXTENSION IF NOT EXISTS pgtap WITH SCHEMA extensions;

SELECT plan(12);

-- Global assertions
SELECT extensions.is(
  (
    SELECT array_agg(c.relname::text ORDER BY c.relname)
    FROM pg_class AS c
    JOIN pg_namespace AS n ON n.oid = c.relnamespace
    WHERE n.nspname = 'public' AND c.relkind IN ('r', 'p') AND NOT c.relrowsecurity
  ),
  NULL::text[],
  'every table in public has Row Level Security enabled'
);

SELECT extensions.is(
  (
    SELECT array_agg(p.proname::text ORDER BY p.proname)
    FROM pg_proc AS p
    JOIN pg_namespace AS n ON n.oid = p.pronamespace
    WHERE
      n.nspname = 'public'
      AND p.prosecdef
      AND NOT EXISTS (
        SELECT
        FROM unnest(coalesce(p.proconfig, '{}')) AS setting
        WHERE setting LIKE 'search_path=%'
      )
  ),
  NULL::text[],
  'every SECURITY DEFINER function in public sets its search_path'
);

SELECT todo('Iteration 1 task DB-7 revokes the default anon privileges', 1);

SELECT extensions.is(
  (
    SELECT array_agg(DISTINCT table_name::text ORDER BY table_name::text)
    FROM information_schema.role_table_grants
    WHERE grantee = 'anon' AND table_schema = 'public'
  ),
  NULL::text[],
  'anon has no privileges on tables in public'
);

-- No policies exist yet (Iteration 1 tasks DB-2 and DB-6), so nobody reads anything through the
-- Data API roles.
SET LOCAL ROLE anon;

SELECT is_empty('select 1 from public.activities', 'anon reads no activities');

SELECT is_empty('select 1 from public.profiles', 'anon reads no profiles');

SET LOCAL ROLE authenticated;

SELECT is_empty(
  'select 1 from public.profile_private',
  'a signed-in user reads no private data yet'
);

RESET role;

-- The on_auth_user_created trigger
INSERT INTO auth.users
  (id, email, raw_user_meta_data)
VALUES
  ('a0000000-0000-4000-8000-000000000001', 'pat.tester@byui.edu', '{"full_name": "Pat Tester"}'),
  ('a0000000-0000-4000-8000-000000000002', 'jo.smith@byui.edu', '{}'),
  ('a0000000-0000-4000-8000-000000000003', 'x@byui.edu', '{}');

SELECT extensions.is(
  (
    SELECT display_name
    FROM public.profiles
    WHERE id = 'a0000000-0000-4000-8000-000000000001'
  ),
  'Pat Tester',
  'a new user gets a profile named from Google'
);

SELECT extensions.is(
  (
    SELECT email::text
    FROM public.profile_private
    WHERE user_id = 'a0000000-0000-4000-8000-000000000001'
  ),
  'pat.tester@byui.edu',
  'the email goes to profile_private'
);

SELECT extensions.is(
  (
    SELECT display_name
    FROM public.profiles
    WHERE id = 'a0000000-0000-4000-8000-000000000002'
  ),
  'jo.smith',
  'without a Google name, the profile uses the part of the email before the @'
);

SELECT extensions.is(
  (
    SELECT display_name
    FROM public.profiles
    WHERE id = 'a0000000-0000-4000-8000-000000000003'
  ),
  'Member',
  'a name shorter than 2 characters falls back to Member'
);

-- Categories
SELECT extensions.is(
  (
    SELECT count(*)::INTEGER
    FROM public.categories
    WHERE is_active
  ),
  9,
  'nine categories are active'
);

SELECT extensions.is(
  (
    SELECT is_active
    FROM public.categories
    WHERE id = 'online'
  ),
  FALSE,
  'Online & Remote is inactive while FABA serves Rexburg only (ADR-017)'
);

SELECT *
FROM finish();

ROLLBACK;
