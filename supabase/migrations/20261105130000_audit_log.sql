-- The audit log (MOD-05): an append-only record of moderation and role changes, account deletions
-- and admin data fixes. Design document sections 9.8 and 10.3, and FR-MOD-4. It lives in the
-- private schema, which the Data API never exposes. In Phase 1, admins read it in the Supabase
-- dashboard (docs/runbooks/audit-log.md).
CREATE TABLE private.audit_log (
  id BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  -- Who did it. No foreign key, so the row outlives a deleted account (PROF-05). Null when an
  -- admin runs a runbook in the dashboard, where nobody is signed in.
  actor_id uuid,
  action text NOT NULL CHECK (
    action IN
      (
        'hide',
        'unhide',
        'suspend',
        'reinstate',
        'dismiss_report',
        'set_role',
        'delete_account',
        'data_fix'
      )
  ),
  target_type text NOT NULL CHECK (target_type IN ('activity', 'profile', 'report')),
  target_id uuid NOT NULL,
  reason text CHECK (char_length(reason) <= 500),
  -- Details such as the old and new role. Never personal data such as names or emails (PROF-05).
  metadata jsonb NOT NULL DEFAULT '{}',
  created_at timestamptz NOT NULL DEFAULT now()
);

CREATE INDEX audit_log_target_idx ON private.audit_log (target_type, target_id);

CREATE INDEX audit_log_actor_idx ON private.audit_log (actor_id, created_at);

CREATE INDEX audit_log_created_at_idx ON private.audit_log (created_at);

-- Only the database owner reads or writes it: not members, visitors, or the Worker's secret key.
-- Row Level Security with no policies backs that up.
REVOKE ALL ON private.audit_log FROM PUBLIC, anon, authenticated, service_role;

ALTER TABLE private.audit_log ENABLE ROW LEVEL SECURITY;

-- Rows can't change, even for the owner, so even a SECURITY DEFINER function can only add them.
-- A row can be deleted only after the 3 years it's kept (section 9.14), for the retention job.
CREATE FUNCTION private.audit_log_append_only()
RETURNS trigger
LANGUAGE plpgsql
SET search_path = ''
AS $$
begin
  if tg_op = 'DELETE' and old.created_at < now() - interval '3 years' then
    return old;
  end if;

  raise exception 'AUDIT_LOG_APPEND_ONLY' using errcode = '42501';
end;
$$;

CREATE TRIGGER audit_log_append_only
BEFORE UPDATE OR DELETE ON private.audit_log
FOR EACH ROW
EXECUTE FUNCTION private.audit_log_append_only();

-- Writes an audit row. Moderation and admin functions call it in the same transaction as the
-- change, so both are saved or neither is. The actor is the signed-in member. Only the owner can
-- call it, so members can't write rows of their own.
CREATE FUNCTION private.audit(
  action text,
  target_type text,
  target_id uuid,
  reason text DEFAULT NULL,
  metadata jsonb DEFAULT '{}'
)
RETURNS void
LANGUAGE sql
SET search_path = ''
AS $$
  INSERT INTO private.audit_log (actor_id, action, target_type, target_id, reason, metadata)
  VALUES
    (
      auth.uid(),
      audit.action,
      audit.target_type,
      audit.target_id,
      nullif(trim(audit.reason), ''),
      coalesce(audit.metadata, '{}')
    );
$$;

REVOKE EXECUTE
ON FUNCTION private.audit(text, text, uuid, text, jsonb)
FROM PUBLIC, anon, authenticated, service_role;
