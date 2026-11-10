-- Reporting and hiding organizer updates (NOTIF-04, FR-REP-3). Design document sections 8.10, 9.8
-- and 10.3. Members report an update as they report an activity or a member. Moderators hide it
-- from the reports queue, with a reason that goes to the audit log, which deals with its open
-- reports too. A hidden update leaves the activity's page and Alerts for everyone but its author,
-- who sees why, and moderators, who can unhide it. As with activities (MOD-03).

ALTER TABLE public.reports
DROP CONSTRAINT reports_target_type_check;

ALTER TABLE public.reports
ADD CONSTRAINT reports_target_type_check
  CHECK (target_type IN ('activity', 'profile', 'activity_update'));

ALTER TABLE private.audit_log
DROP CONSTRAINT audit_log_target_type_check;

ALTER TABLE private.audit_log
ADD CONSTRAINT audit_log_target_type_check
  CHECK (target_type IN ('activity', 'profile', 'report', 'activity_update'));

-- Why it was hidden, which its author sees, and who hid it, as on activities.
ALTER TABLE public.activity_updates
ADD COLUMN hidden_reason text CHECK (char_length(hidden_reason) <= 500),
ADD COLUMN hidden_by uuid REFERENCES public.profiles (id)
  ON DELETE SET NULL;

-- Members read the updates to the activities they can see, as before
-- (20261109130000_activity_updates.sql). Its author and moderators read a hidden one too.
DROP POLICY "Active members read updates to the activities they can see" ON public.activity_updates;

CREATE POLICY "Active members read updates to the activities they can see" ON public.activity_updates
FOR SELECT
TO authenticated
USING (
  (SELECT private.is_active_member())
  AND (
    activity_updates.hidden_at IS NULL
    OR activity_updates.author_id = (SELECT auth.uid())
    OR (SELECT private.is_moderator()) IS TRUE
  )
  AND EXISTS (SELECT FROM public.activities AS a WHERE a.id = activity_updates.activity_id)
);

-- Reporting, as before (20261105140000_reports.sql), and now an update too: one that isn't hidden,
-- to an activity that isn't. Not one the member posted.
CREATE OR REPLACE FUNCTION public.report_content(
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
  elsif report_content.target_type = 'activity_update' then
    select u.author_id into owner
    from public.activity_updates as u
    join public.activities as a on a.id = u.activity_id
    where u.id = report_content.target_id and u.hidden_at is null and a.hidden_at is null;
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

-- Hides an update, with a reason its author sees. Only moderators and admins can. Its open reports
-- are dealt with, so they leave the queue.
CREATE FUNCTION public.moderate_hide_update(update_id uuid, reason text)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
declare
  posted public.activity_updates;
  why text := nullif(trim(moderate_hide_update.reason), '');
  actioned integer;
begin
  if not private.is_moderator() then
    raise exception 'NOT_MODERATOR' using errcode = '42501';
  end if;

  if why is null then
    raise exception 'REASON_REQUIRED' using errcode = '22023';
  end if;

  select * into posted
  from public.activity_updates as u
  where u.id = moderate_hide_update.update_id
  for update;

  if not found then
    raise exception 'UPDATE_NOT_FOUND' using errcode = 'P0002';
  end if;

  if posted.hidden_at is not null then
    raise exception 'UPDATE_ALREADY_HIDDEN' using errcode = '22023';
  end if;

  update public.activity_updates as u
  set hidden_at = now(), hidden_reason = why, hidden_by = auth.uid()
  where u.id = posted.id;

  update public.reports as r
  set status = 'actioned', resolved_by = auth.uid(), resolved_at = now(), resolution_note = why
  where r.target_type = 'activity_update' and r.target_id = posted.id and r.status = 'open';
  get diagnostics actioned = row_count;

  perform private.audit(
    'hide',
    'activity_update',
    posted.id,
    why,
    jsonb_build_object('activity_id', posted.activity_id, 'reports_actioned', actioned)
  );
end;
$$;

-- Unhides an update, with a reason for the audit log. Only moderators and admins can.
CREATE FUNCTION public.moderate_unhide_update(update_id uuid, reason text)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
declare
  posted public.activity_updates;
  why text := nullif(trim(moderate_unhide_update.reason), '');
begin
  if not private.is_moderator() then
    raise exception 'NOT_MODERATOR' using errcode = '42501';
  end if;

  if why is null then
    raise exception 'REASON_REQUIRED' using errcode = '22023';
  end if;

  select * into posted
  from public.activity_updates as u
  where u.id = moderate_unhide_update.update_id
  for update;

  if not found then
    raise exception 'UPDATE_NOT_FOUND' using errcode = 'P0002';
  end if;

  if posted.hidden_at is null then
    raise exception 'UPDATE_NOT_HIDDEN' using errcode = '22023';
  end if;

  update public.activity_updates as u
  set hidden_at = null, hidden_reason = null, hidden_by = null
  where u.id = posted.id;

  perform private.audit(
    'unhide',
    'activity_update',
    posted.id,
    why,
    jsonb_build_object('activity_id', posted.activity_id, 'hidden_reason', posted.hidden_reason)
  );
end;
$$;

GRANT EXECUTE ON FUNCTION public.moderate_hide_update(uuid, text) TO authenticated;

GRANT EXECUTE ON FUNCTION public.moderate_unhide_update(uuid, text) TO authenticated;
