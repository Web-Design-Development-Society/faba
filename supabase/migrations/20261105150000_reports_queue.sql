-- The moderators' reports queue (MOD-02). Design document sections 9.8 and 10.3, and FR-MOD-1.
-- Moderators read every report, and dismiss one with a reason that goes to the audit log
-- (MOD-05). Hiding content (MOD-03) and suspending a member (MOD-04) will resolve reports too.

-- An active member whose role is moderator or admin. Roles are read from the database, not the
-- JWT, so a change applies on the next request (section 9.8).
CREATE FUNCTION private.is_moderator()
RETURNS BOOLEAN
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = ''
AS $$
  SELECT private.is_active_member()
  AND EXISTS (
    SELECT
    FROM public.profiles
    WHERE id = auth.uid() AND role IN ('moderator', 'admin')
  );
$$;

GRANT EXECUTE ON FUNCTION private.is_moderator() TO authenticated;

-- Who resolved a report, when, and why. The reason goes to the audit log too.
ALTER TABLE public.reports
ADD COLUMN resolved_by uuid REFERENCES public.profiles (id)
  ON DELETE SET NULL,
ADD COLUMN resolved_at timestamptz,
ADD COLUMN resolution_note text CHECK (char_length(resolution_note) <= 500),
ADD CONSTRAINT reports_resolved_check CHECK ((status = 'open') = (resolved_at IS NULL));

-- Moderators read every report. Members still read only their own.
DROP POLICY "Members read their own reports" ON public.reports;

CREATE POLICY "Members read their own reports, and moderators read all" ON public.reports
FOR SELECT
TO authenticated
USING (reporter_id = (SELECT auth.uid()) OR (SELECT private.is_moderator()) IS TRUE);

-- Dismisses an open report: nothing needed doing. Only moderators and admins can, and they say
-- why, in the same transaction as the audit row.
CREATE FUNCTION public.dismiss_report(report_id uuid, reason text)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
declare
  report public.reports;
  why text := nullif(trim(dismiss_report.reason), '');
begin
  if not private.is_moderator() then
    raise exception 'NOT_MODERATOR' using errcode = '42501';
  end if;

  if why is null then
    raise exception 'REASON_REQUIRED' using errcode = '22023';
  end if;

  select * into report
  from public.reports as r
  where r.id = dismiss_report.report_id
  for update;

  if not found or report.status <> 'open' then
    raise exception 'REPORT_NOT_OPEN' using errcode = 'P0002';
  end if;

  update public.reports as r
  set status = 'dismissed', resolved_by = auth.uid(), resolved_at = now(), resolution_note = why
  where r.id = report.id;

  perform private.audit(
    'dismiss_report',
    'report',
    report.id,
    why,
    jsonb_build_object('target_type', report.target_type, 'target_id', report.target_id)
  );
end;
$$;

GRANT EXECUTE ON FUNCTION public.dismiss_report(uuid, text) TO authenticated;
