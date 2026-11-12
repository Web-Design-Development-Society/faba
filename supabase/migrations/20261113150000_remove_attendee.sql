-- Managing the attendee list (RSVP-09). Design document section 6.6 Phase 3 and FR-ACT-12. The
-- organizer and co-organizers (ACT-10), a moderator, and an organizer of the activity's group can
-- remove an attendee, and read the names of everyone going as a CSV export. Removing an attendee
-- frees their spot, so the waitlist (RSVP-07) moves on through the existing trigger. They're told,
-- and they can say "I'm in" again.

ALTER TABLE public.notifications
DROP CONSTRAINT notifications_type_check;

ALTER TABLE public.notifications
ADD CONSTRAINT notifications_type_check
  CHECK (
    type IN (
      'activity_changed',
      'activity_cancelled',
      'activity_restored',
      'organizer_update',
      'rsvp_confirmed',
      'new_attendees',
      'reminder',
      'board_announcement',
      'group_join_request',
      'group_update',
      'group_join_approved',
      'group_owner',
      'rsvp_promoted',
      'rsvp_removed'
    )
  );

-- Whether the caller can manage the attendee list of `activity_id`: its organizer or a
-- co-organizer, a moderator, or an owner or organizer of its group.
CREATE FUNCTION private.can_manage_attendees(activity_id uuid)
RETURNS BOOLEAN
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = ''
AS $$
  SELECT private.is_active_member()
  AND (
    private.is_activity_organizer(can_manage_attendees.activity_id)
    OR private.is_moderator()
    OR EXISTS (
      SELECT
      FROM public.activities AS a
      JOIN public.group_members AS m ON m.group_id = a.group_id
      WHERE
        a.id = can_manage_attendees.activity_id
        AND m.user_id = (SELECT auth.uid())
        AND m.role IN ('owner', 'organizer')
        AND m.status = 'active'
    )
  );
$$;

GRANT EXECUTE ON FUNCTION private.can_manage_attendees(uuid) TO authenticated;

-- Whether the caller can manage the attendee list, so the page shows its controls. Reveals nothing
-- else.
CREATE FUNCTION public.manages_attendees(activity_id uuid)
RETURNS BOOLEAN
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = ''
AS $$
  SELECT private.can_manage_attendees(manages_attendees.activity_id);
$$;

GRANT EXECUTE ON FUNCTION public.manages_attendees(uuid) TO authenticated;

-- Removes `user_id` from `activity_id`'s attendee list. Only those who can manage it can, and never
-- the organizer. Their RSVP stops counting (going, maybe, guests, or the waitlist), and they get an
-- rsvp_removed notification. Removing someone who isn't on the list changes nothing.
CREATE FUNCTION public.remove_attendee(activity_id uuid, user_id uuid)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
declare
  activity public.activities;
  removed public.rsvps;
begin
  if not private.is_active_member() then
    raise exception 'NOT_ACTIVE' using errcode = '42501';
  end if;

  -- Locked, so this doesn't race an RSVP to the same activity.
  select * into activity
  from public.activities as a
  where a.id = remove_attendee.activity_id
  for update;

  if not found or not private.can_manage_attendees(activity.id) then
    raise exception 'NOT_ATTENDEE_MANAGER' using errcode = '42501';
  end if;

  if remove_attendee.user_id = activity.organizer_id then
    raise exception 'CANNOT_REMOVE_ORGANIZER' using errcode = '22023';
  end if;

  select r.* into removed
  from public.rsvps as r
  where r.activity_id = activity.id and r.user_id = remove_attendee.user_id;

  if not found or removed.status = 'not_going' then
    return;
  end if;

  update public.rsvps as r
  set status = 'not_going', guest_count = 0, waitlisted_at = null
  where r.activity_id = activity.id and r.user_id = remove_attendee.user_id;

  -- A spot that opens here goes to the waitlist through activities_promote_waitlist.
  update public.activities as a
  set
    going_count = a.going_count - (case when removed.status = 'going' then 1 else 0 end),
    maybe_count = a.maybe_count - (case when removed.status = 'maybe' then 1 else 0 end),
    guest_total = a.guest_total
      - (case when removed.status = 'going' then coalesce(removed.guest_count, 0) else 0 end)
  where a.id = activity.id;

  -- Their confirmation for going goes, as when they say they can't make it (NOTIF-05).
  delete from public.notifications as n
  where n.recipient_id = remove_attendee.user_id and n.dedupe_key = 'rsvp_confirmed:' || activity.id;

  perform private.notify(
    array[remove_attendee.user_id],
    'rsvp_removed',
    activity.id,
    jsonb_build_object(
      'title', activity.title,
      'starts_at', activity.starts_at,
      'location_name', activity.location_name
    ),
    'rsvp_removed:' || activity.id || ':' || remove_attendee.user_id
  );
end;
$$;

GRANT EXECUTE ON FUNCTION public.remove_attendee(uuid, uuid) TO authenticated;

-- The names of everyone going to `activity_id`, for the CSV export (RSVP-09). Names only: no guest
-- counts, and no one who is suspended. Those who can manage the attendee list only.
CREATE FUNCTION public.attendee_names(activity_id uuid)
RETURNS SETOF text
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
begin
  if not private.can_manage_attendees(attendee_names.activity_id) then
    raise exception 'NOT_ATTENDEE_MANAGER' using errcode = '42501';
  end if;

  return query
    select p.display_name
    from public.rsvps as r
    join public.profiles as p on p.id = r.user_id
    where r.activity_id = attendee_names.activity_id
      and r.status = 'going'
      and p.status = 'active'
    order by p.display_name, p.id;
end;
$$;

GRANT EXECUTE ON FUNCTION public.attendee_names(uuid) TO authenticated;
