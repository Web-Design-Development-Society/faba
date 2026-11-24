-- Keeping a free database awake (OPS-05). Run with `npm run db:test`.
BEGIN;

CREATE EXTENSION IF NOT EXISTS pgtap WITH SCHEMA extensions;

SELECT plan(4);

SELECT extensions.is(
  (
    SELECT p.prosecdef
    FROM pg_proc AS p
    WHERE p.oid = 'public.keep_awake()'::regprocedure
  ),
  FALSE,
  'keep_awake() runs as its caller, not as its owner'
);

SELECT ok(
  NOT has_function_privilege('public', 'public.keep_awake()', 'execute'),
  'not every role can run it, only the ones granted'
);

-- The Worker calls it with the publishable key, which is the anon role.
SET LOCAL ROLE anon;

SELECT extensions.is(public.keep_awake(), TRUE, 'anon can run it');

SELECT throws_ok('select id from public.categories', '42501', NULL, 'and still reads no table');

SELECT *
FROM finish();

ROLLBACK;
