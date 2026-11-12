-- Automatic data retention (PRIV-02). Design document section 9.14 sets how long each kind of data
-- is kept. Every night, `private.enforce_retention()` deletes what has run out, and records how many
-- rows each run removed in `retention_runs`:
--   * Private details (an address and the like): 30 days after the activity ends (or starts, if it has
--     no end). The activity stays; its details go, and its flag is cleared.
--   * Notifications: 90 days.
--   * Reports: 2 years after they were resolved. Open reports stay.
--   * Audit log: 3 years. The append-only trigger allows that delete and no other.

CREATE TABLE public.retention_runs (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  ran_at timestamptz NOT NULL DEFAULT now(),
  target text NOT NULL CHECK (
    target IN ('private_details', 'notifications', 'reports', 'audit_log')
  ),
  removed INTEGER NOT NULL CHECK (removed >= 0)
);

CREATE INDEX retention_runs_ran_idx ON public.retention_runs (ran_at);

-- Only the scheduled job and the owner read these counts. No app role has any access.
ALTER TABLE public.retention_runs ENABLE ROW LEVEL SECURITY;

-- Runs every retention rule, and returns how many rows it removed in total.
CREATE FUNCTION private.enforce_retention()
RETURNS INTEGER
LANGUAGE plpgsql
SET search_path = ''
AS $$
declare
  removed_details INTEGER;
  removed_notifications INTEGER;
  removed_reports INTEGER;
  removed_audit INTEGER;
begin
  with gone as (
    delete from public.activity_private_details as d
    using public.activities as a
    where a.id = d.activity_id
      and coalesce(a.ends_at, a.starts_at) < now() - interval '30 days'
    returning 1
  )
  select count(*)::INTEGER into removed_details from gone;

  update public.activities as a
  set has_private_details = false
  where a.has_private_details
    and coalesce(a.ends_at, a.starts_at) < now() - interval '30 days';

  with gone as (
    delete from public.notifications as n
    where n.created_at < now() - interval '90 days'
    returning 1
  )
  select count(*)::INTEGER into removed_notifications from gone;

  with gone as (
    delete from public.reports as r
    where r.status <> 'open' and r.resolved_at < now() - interval '2 years'
    returning 1
  )
  select count(*)::INTEGER into removed_reports from gone;

  with gone as (
    delete from private.audit_log as l
    where l.created_at < now() - interval '3 years'
    returning 1
  )
  select count(*)::INTEGER into removed_audit from gone;

  insert into public.retention_runs (target, removed)
  values
    ('private_details', removed_details),
    ('notifications', removed_notifications),
    ('reports', removed_reports),
    ('audit_log', removed_audit);

  return removed_details + removed_notifications + removed_reports + removed_audit;
end;
$$;

REVOKE EXECUTE
ON FUNCTION private.enforce_retention()
FROM PUBLIC, anon, authenticated, service_role;

-- Runs at 10:45 UTC, after the 90-day notification job at 10:30, which it leaves alone.
SELECT cron.schedule('enforce-retention', '45 10 * * *', 'select private.enforce_retention()');
