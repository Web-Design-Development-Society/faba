-- Cancelling and restoring an activity (ACT-05). Design document sections 9.9, 10.3 and 10.5.

-- An optional short reason, shown in the Cancelled banner.
ALTER TABLE public.activities
ADD CONSTRAINT activities_cancel_reason_check CHECK (char_length(cancel_reason) <= 200);

-- Cancels an activity, with an optional reason. Only its organizer can, at any time, so one that
-- didn't happen can say so afterwards. It stays, with its URL and RSVPs, so attendees still find
-- it, marked cancelled. RSVPs close (rsvp()), and the feed leaves it out (get_feed()). Cancelling
-- it again changes nothing.
CREATE FUNCTION public.cancel_activity(activity_id uuid, reason text DEFAULT NULL)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
declare
  activity public.activities;
begin
  if not private.is_active_member() then
    raise exception 'NOT_ACTIVE' using errcode = '42501';
  end if;

  select * into activity
  from public.activities as a
  where a.id = cancel_activity.activity_id
  for update;

  -- The same for an activity that doesn't exist, so nobody learns which ones do.
  if not found or activity.organizer_id is distinct from auth.uid() then
    raise exception 'NOT_ORGANIZER' using errcode = '42501';
  end if;

  if activity.status = 'cancelled' then
    return;
  end if;

  update public.activities as a
  set
    status = 'cancelled',
    cancel_reason = nullif(trim(cancel_activity.reason), ''),
    cancelled_at = now()
  where a.id = activity.id;
end;
$$;

-- Puts a cancelled activity back on, until it starts (ACT-05). Restoring one that isn't cancelled
-- changes nothing.
CREATE FUNCTION public.restore_activity(activity_id uuid)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
declare
  activity public.activities;
begin
  if not private.is_active_member() then
    raise exception 'NOT_ACTIVE' using errcode = '42501';
  end if;

  select * into activity
  from public.activities as a
  where a.id = restore_activity.activity_id
  for update;

  if not found or activity.organizer_id is distinct from auth.uid() then
    raise exception 'NOT_ORGANIZER' using errcode = '42501';
  end if;

  if activity.status = 'published' then
    return;
  end if;

  if activity.starts_at <= now() then
    raise exception 'RESTORE_TOO_LATE' using errcode = '22023';
  end if;

  update public.activities as a
  set status = 'published', cancel_reason = null, cancelled_at = null
  where a.id = activity.id;
end;
$$;

GRANT EXECUTE ON FUNCTION public.cancel_activity(uuid, text) TO authenticated;

GRANT EXECUTE ON FUNCTION public.restore_activity(uuid) TO authenticated;
