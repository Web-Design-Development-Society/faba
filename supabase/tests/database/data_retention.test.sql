-- Automatic data retention (PRIV-02). Run with `npm run db:test`.
BEGIN;

CREATE EXTENSION IF NOT EXISTS pgtap WITH SCHEMA extensions;

SELECT plan(4);

-- An audit row older than 3 years goes, and a recent one stays. The run records what it removed.
INSERT INTO private.audit_log
  (actor_id, action, target_type, target_id, reason, metadata, created_at)
VALUES
  (NULL, 'data_fix', 'profile', gen_random_uuid(), 'Old row', '{}', now() - INTERVAL '4 years'),
  (NULL, 'data_fix', 'profile', gen_random_uuid(), 'New row', '{}', now() - INTERVAL '1 day');

SELECT cmp_ok(private.enforce_retention(), '>=', 1, 'the retention run removes what has run out');

SELECT results_eq(
  $$select count(*) from private.audit_log where reason = 'Old row'$$,
  $$values (0::bigint)$$,
  'an audit row past three years is removed'
);

SELECT results_eq(
  $$select count(*) from private.audit_log where reason = 'New row'$$,
  $$values (1::bigint)$$,
  'a recent audit row stays'
);

SELECT results_eq(
  $$select count(*) from public.retention_runs where target = 'audit_log' and removed >= 1$$,
  $$values (1::bigint)$$,
  'the run records how many audit rows it removed'
);

ROLLBACK;
