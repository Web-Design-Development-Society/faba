-- Organizer updates as before (20261109130000_activity_updates.sql), with their own error for the
-- daily limit, like REPORT_QUOTA_EXCEEDED, so the app doesn't say it's the limit on activities
-- (NOTIF-04).
CREATE OR REPLACE FUNCTION public.post_activity_update(
  activity_id uuid,
  body text,
  idempotency_key uuid DEFAULT NULL
)
RETURNS uuid
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
declare
  activity public.activities;
  posted text := btrim(post_activity_update.body, E' \t\r\n');
  new_id uuid;
begin
  if not private.is_active_member() then
    raise exception 'NOT_ACTIVE' using errcode = '42501';
  end if;

  -- Locked, so updates to one activity count one at a time.
  select * into activity
  from public.activities as a
  where a.id = post_activity_update.activity_id
  for update;

  -- The same for an activity that doesn't exist, so nobody learns which ones do.
  if not found or activity.organizer_id is distinct from auth.uid() then
    raise exception 'NOT_ORGANIZER' using errcode = '42501';
  end if;

  if post_activity_update.idempotency_key is not null then
    select u.id into new_id
    from public.activity_updates as u
    where u.author_id = auth.uid() and u.idempotency_key = post_activity_update.idempotency_key;

    if found then
      return new_id;
    end if;
  end if;

  -- Nobody but its organizer can see a hidden activity, so it tells nobody anything.
  if activity.hidden_at is not null then
    raise exception 'ACTIVITY_HIDDEN' using errcode = '22023';
  end if;

  if posted is null or char_length(posted) not between 1 and 500 then
    raise exception 'INVALID_BODY' using errcode = '22023';
  end if;

  -- At most 5 to an activity in 24 hours, hidden ones included (NOTIF-04).
  if (
    select count(*)
    from public.activity_updates as u
    where u.activity_id = activity.id and u.created_at > now() - interval '24 hours'
  ) >= 5 then
    raise exception 'UPDATE_QUOTA_EXCEEDED' using errcode = 'P0001';
  end if;

  insert into public.activity_updates (activity_id, author_id, body, idempotency_key)
  values (activity.id, auth.uid(), posted, post_activity_update.idempotency_key)
  returning id into new_id;

  perform private.notify_attendees(
    activity.id,
    'organizer_update',
    jsonb_build_object('update_id', new_id, 'title', activity.title, 'starts_at', activity.starts_at)
  );

  return new_id;
end;
$$;
