-- Hiding and unhiding an activity (MOD-03). Design document sections 9.8 and 10.3, and FR-MOD-1.
-- A hidden activity leaves every list, and its page, for everyone but its organizer, who sees why,
-- and moderators. Moderators never edit it. They hide it, the organizer can edit it, and then a
-- moderator can unhide it. Both write to the audit log (MOD-05).

-- Moderators read hidden activities too.
DROP POLICY "Active members read activities that aren't hidden" ON public.activities;

CREATE POLICY "Active members read activities that aren't hidden, and moderators read all" ON public.activities
FOR SELECT
TO authenticated
USING (
  (SELECT private.is_active_member())
  AND (
    hidden_at IS NULL
    OR organizer_id = (SELECT auth.uid())
    OR (SELECT private.is_moderator()) IS TRUE
  )
);

-- The reason the organizer sees in the banner.
ALTER TABLE public.activities
ADD CONSTRAINT activities_hidden_reason_check CHECK (char_length(hidden_reason) <= 500);

-- Hides an activity, with a reason its organizer sees. Only moderators and admins can. Its open
-- reports are dealt with, so they leave the queue.
CREATE FUNCTION public.moderate_hide(activity_id uuid, reason text)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
declare
  activity public.activities;
  why text := nullif(trim(moderate_hide.reason), '');
  actioned integer;
begin
  if not private.is_moderator() then
    raise exception 'NOT_MODERATOR' using errcode = '42501';
  end if;

  if why is null then
    raise exception 'REASON_REQUIRED' using errcode = '22023';
  end if;

  select * into activity
  from public.activities as a
  where a.id = moderate_hide.activity_id
  for update;

  if not found then
    raise exception 'ACTIVITY_NOT_FOUND' using errcode = 'P0002';
  end if;

  if activity.hidden_at is not null then
    raise exception 'ALREADY_HIDDEN' using errcode = '22023';
  end if;

  update public.activities as a
  set hidden_at = now(), hidden_reason = why, hidden_by = auth.uid()
  where a.id = activity.id;

  update public.reports as r
  set status = 'actioned', resolved_by = auth.uid(), resolved_at = now(), resolution_note = why
  where r.target_type = 'activity' and r.target_id = activity.id and r.status = 'open';
  get diagnostics actioned = row_count;

  perform private.audit(
    'hide',
    'activity',
    activity.id,
    why,
    jsonb_build_object('reports_actioned', actioned)
  );
end;
$$;

-- Unhides an activity, with a reason for the audit log, such as the organizer having fixed it.
-- Only moderators and admins can.
CREATE FUNCTION public.moderate_unhide(activity_id uuid, reason text)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
declare
  activity public.activities;
  why text := nullif(trim(moderate_unhide.reason), '');
begin
  if not private.is_moderator() then
    raise exception 'NOT_MODERATOR' using errcode = '42501';
  end if;

  if why is null then
    raise exception 'REASON_REQUIRED' using errcode = '22023';
  end if;

  select * into activity
  from public.activities as a
  where a.id = moderate_unhide.activity_id
  for update;

  if not found then
    raise exception 'ACTIVITY_NOT_FOUND' using errcode = 'P0002';
  end if;

  if activity.hidden_at is null then
    raise exception 'NOT_HIDDEN' using errcode = '22023';
  end if;

  update public.activities as a
  set hidden_at = null, hidden_reason = null, hidden_by = null
  where a.id = activity.id;

  perform private.audit(
    'unhide',
    'activity',
    activity.id,
    why,
    jsonb_build_object('hidden_reason', activity.hidden_reason)
  );
end;
$$;

GRANT EXECUTE ON FUNCTION public.moderate_hide(uuid, text) TO authenticated;

GRANT EXECUTE ON FUNCTION public.moderate_unhide(uuid, text) TO authenticated;
