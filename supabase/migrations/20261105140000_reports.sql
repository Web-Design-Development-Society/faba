-- Reporting an activity or a member (MOD-01). Design document sections 8.10, 9.8 and 10.3, and
-- FR-REP-1 and FR-REP-2. Reports never hide anything by themselves in Phase 1. Moderators read and
-- resolve them with MOD-02, which adds who resolved each one and how.
CREATE TABLE public.reports (
  -- A uuid, so the audit log can name a report as its target (MOD-05).
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  -- Null after the reporter deletes their account (PROF-05).
  reporter_id uuid REFERENCES public.profiles (id)
    ON DELETE SET NULL,
  -- No foreign key, since it's an activity or a profile. A report outlives what it's about.
  target_type text NOT NULL CHECK (target_type IN ('activity', 'profile')),
  target_id uuid NOT NULL,
  reason text NOT NULL CHECK (reason IN ('inappropriate', 'spam', 'unsafe', 'other')),
  note text CHECK (char_length(note) <= 500),
  status text NOT NULL DEFAULT 'open' CHECK (status IN ('open', 'dismissed', 'actioned')),
  created_at timestamptz NOT NULL DEFAULT now(),
  -- Once per member for each activity or member (FR-REP-2).
  UNIQUE (reporter_id, target_type, target_id)
);

-- The moderators' queue, oldest first (MOD-02).
CREATE INDEX reports_open_idx ON public.reports (created_at)
WHERE status = 'open';

-- The daily limit.
CREATE INDEX reports_reporter_idx ON public.reports (reporter_id, created_at);

ALTER TABLE public.reports ENABLE ROW LEVEL SECURITY;

-- Members read only their own reports, so the form can say they've sent one. Moderators get access
-- with MOD-02. Nobody else learns who reported what (FR-REP-1). Writes go through report_content().
CREATE POLICY "Members read their own reports" ON public.reports
FOR SELECT
TO authenticated
USING (reporter_id = (SELECT auth.uid()));

-- Reports an activity or a member, with a reason and an optional note. Returns the report's id.
-- Only what the member can see: an activity that isn't hidden, or an active member's profile. Not
-- their own. Once per target, and at most 10 in 24 hours (FR-REP-2).
CREATE FUNCTION public.report_content(
  target_type text,
  target_id uuid,
  reason text,
  note text DEFAULT NULL
)
RETURNS uuid
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
declare
  owner uuid;
  report_id uuid;
begin
  if not private.is_active_member() then
    raise exception 'NOT_ACTIVE' using errcode = '42501';
  end if;

  if report_content.target_type = 'activity' then
    select a.organizer_id into owner
    from public.activities as a
    where a.id = report_content.target_id and a.hidden_at is null;
  elsif report_content.target_type = 'profile' then
    select p.id into owner
    from public.profiles as p
    where p.id = report_content.target_id and p.status = 'active';
  end if;

  if not found then
    raise exception 'REPORT_TARGET_NOT_FOUND' using errcode = 'P0002';
  end if;

  if owner = auth.uid() then
    raise exception 'REPORT_OWN' using errcode = '22023';
  end if;

  if exists (
    select
    from public.reports as r
    where
      r.reporter_id = auth.uid()
      and r.target_type = report_content.target_type
      and r.target_id = report_content.target_id
  ) then
    raise exception 'ALREADY_REPORTED' using errcode = '23505';
  end if;

  if (
    select count(*)
    from public.reports as r
    where r.reporter_id = auth.uid() and r.created_at > now() - interval '24 hours'
  ) >= 10 then
    raise exception 'REPORT_QUOTA_EXCEEDED' using errcode = 'P0001';
  end if;

  insert into public.reports (reporter_id, target_type, target_id, reason, note)
  values (
    auth.uid(),
    report_content.target_type,
    report_content.target_id,
    report_content.reason,
    nullif(trim(report_content.note), '')
  )
  returning id into report_id;

  return report_id;
end;
$$;

GRANT EXECUTE ON FUNCTION public.report_content(text, uuid, text, text) TO authenticated;
