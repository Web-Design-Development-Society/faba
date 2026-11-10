-- Muting an activity (NOTIF-08). Design document sections 8.8 and 9.12, and FR-NOT-4. A member who's
-- going or maybe, or the organizer, can mute an activity to stop hearing about its changes, updates,
-- new attendees and reminders. Cancelling and restoring it still reach them. A mute belongs to the
-- member's RSVP, as section 10.3 has it, but it's kept in its own table that only they can read,
-- since other members, the organizer included, can read their RSVP. It moves to a new account with
-- the RSVP, and goes when the RSVP does.

CREATE TABLE public.activity_mutes (
  activity_id uuid NOT NULL,
  user_id uuid NOT NULL,
  muted_at timestamptz NOT NULL DEFAULT now(),
  PRIMARY KEY (activity_id, user_id),
  FOREIGN KEY (activity_id, user_id) REFERENCES public.rsvps (activity_id, user_id)
    ON UPDATE CASCADE
    ON DELETE CASCADE
);

ALTER TABLE public.activity_mutes ENABLE ROW LEVEL SECURITY;

-- Members read their own. They mute and unmute through mute_activity().
CREATE POLICY "Members read their own mutes" ON public.activity_mutes
FOR SELECT
TO authenticated
USING (user_id = (SELECT auth.uid()));

-- Mutes `activity_id` for the signed-in member, or unmutes it. Only someone going or maybe can mute
-- an activity, which includes its organizer (RSVP-02). Muting twice, or unmuting what isn't muted,
-- changes nothing.
CREATE FUNCTION public.mute_activity(activity_id uuid, muted BOOLEAN)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
begin
  if not private.is_active_member() then
    raise exception 'NOT_ACTIVE' using errcode = '42501';
  end if;

  if mute_activity.muted is not true then
    delete from public.activity_mutes as m
    where m.activity_id = mute_activity.activity_id and m.user_id = auth.uid();
    return;
  end if;

  if not exists (
    select from public.rsvps as r
    where
      r.activity_id = mute_activity.activity_id
      and r.user_id = auth.uid()
      and r.status in ('going', 'maybe')
  ) then
    raise exception 'NOT_ATTENDING' using errcode = '22023';
  end if;

  insert into public.activity_mutes (activity_id, user_id)
  values (mute_activity.activity_id, auth.uid())
  on conflict do nothing;
end;
$$;

GRANT EXECUTE ON FUNCTION public.mute_activity(uuid, BOOLEAN) TO authenticated;

-- Making notifications as before (20261107130000_activity_changed.sql), but not for a member who
-- muted the activity, when it's a type muting holds back (section 8.8).
CREATE OR REPLACE FUNCTION private.notify(
  recipients uuid[],
  type text,
  activity_id uuid,
  payload jsonb,
  dedupe_key text DEFAULT NULL
)
RETURNS INTEGER
LANGUAGE plpgsql
SET search_path = ''
AS $$
declare
  made integer;
begin
  insert into public.notifications (recipient_id, type, activity_id, actor_id, payload, dedupe_key)
  select distinct
    r.id,
    notify.type,
    notify.activity_id,
    auth.uid(),
    coalesce(notify.payload, '{}'),
    notify.dedupe_key
  from unnest(notify.recipients) as r (id)
  where
    r.id is not null
    and not (
      notify.type in ('activity_changed', 'organizer_update', 'new_attendees', 'reminder')
      and exists (
        select from public.activity_mutes as m
        where m.activity_id = notify.activity_id and m.user_id = r.id
      )
    )
  on conflict on constraint notifications_recipient_id_dedupe_key_key do update
  set
    payload = excluded.payload || jsonb_strip_nulls(
      jsonb_build_object('before', notifications.payload -> 'before')
    ),
    actor_id = excluded.actor_id,
    created_at = now(),
    read_at = null;
  get diagnostics made = row_count;
  return made;
end;
$$;
