-- Organizer updates to attendees (NOTIF-04). Design document sections 8.8, 9.8, 9.12 and 10.3. An
-- organizer posts a short plain-text update to their activity, such as "Bring a headlamp!". Members
-- who can see the activity read its updates, and everyone going or maybe gets organizer_update in
-- the same transaction. Reporting and hiding updates come in a later pull request.

CREATE TABLE public.activity_updates (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  activity_id uuid NOT NULL REFERENCES public.activities (id)
    ON DELETE CASCADE,
  -- Anonymized when its author deletes their account (section 9.14).
  author_id uuid REFERENCES public.profiles (id)
    ON DELETE SET NULL,
  body text NOT NULL CHECK (char_length(body) BETWEEN 1 AND 500),
  -- When a moderator hid it (MOD-03).
  hidden_at timestamptz,
  idempotency_key uuid,
  created_at timestamptz NOT NULL DEFAULT now()
);

-- The activity's page shows them newest first.
CREATE INDEX activity_updates_activity_idx
ON public.activity_updates (activity_id, created_at DESC);

CREATE UNIQUE INDEX activity_updates_idempotency_idx
ON public.activity_updates (author_id, idempotency_key);

ALTER TABLE public.activity_updates ENABLE ROW LEVEL SECURITY;

-- Section 9.8: members read the updates to the activities they can see, unless they're hidden. They
-- post them through post_activity_update().
CREATE POLICY "Active members read updates to the activities they can see" ON public.activity_updates
FOR SELECT
TO authenticated
USING (
  (SELECT private.is_active_member())
  AND activity_updates.hidden_at IS NULL
  AND EXISTS (SELECT FROM public.activities AS a WHERE a.id = activity_updates.activity_id)
);

-- Posts `body` as an update to the signed-in member's activity, and tells everyone going or maybe
-- but them. Updates to a cancelled or past activity are allowed, such as "We'll try again next
-- week". Returns the update's id. A repeated idempotency key returns the update it already posted,
-- so a double tap never posts or notifies twice. The notification holds the update's id, not its
-- text, so hiding an update hides it there too.
CREATE FUNCTION public.post_activity_update(
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
    raise exception 'QUOTA_EXCEEDED' using errcode = 'P0001';
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

GRANT EXECUTE ON FUNCTION public.post_activity_update(uuid, text, uuid) TO authenticated;

-- Moving a member to a new account, as before (20261106240000_guest_counts.sql), now with the
-- updates they posted.
CREATE OR REPLACE FUNCTION private.transfer_account(from_user uuid, to_user uuid, reason text)
RETURNS void
LANGUAGE plpgsql
SET search_path = ''
AS $$
declare
  why text := nullif(trim(transfer_account.reason), '');
  organized integer;
  moved integer;
  dropped integer;
begin
  if why is null then
    raise exception 'REASON_REQUIRED' using errcode = '22023';
  end if;

  if from_user = to_user then
    raise exception 'SAME_ACCOUNT' using errcode = '22023';
  end if;

  if (select count(*) from public.profiles as p where p.id in (from_user, to_user)) < 2 then
    raise exception 'MEMBER_NOT_FOUND' using errcode = 'P0002';
  end if;

  update public.activities as a
  set organizer_id = to_user
  where a.organizer_id = from_user;
  get diagnostics organized = row_count;

  update public.activity_updates as u
  set author_id = to_user
  where u.author_id = from_user;

  -- RSVPs to an activity the new account has also answered go, with the going or maybe count and
  -- the guests they held.
  update public.activities as a
  set
    going_count = a.going_count - (r.status = 'going')::integer,
    maybe_count = a.maybe_count - (r.status = 'maybe')::integer,
    guest_total = a.guest_total - r.guest_count
  from public.rsvps as r
  where
    r.activity_id = a.id
    and r.user_id = from_user
    and r.status in ('going', 'maybe')
    and exists (
      select from public.rsvps as mine where mine.activity_id = a.id and mine.user_id = to_user
    );

  delete from public.rsvps as r
  where
    r.user_id = from_user
    and exists (
      select from public.rsvps as mine
      where mine.activity_id = r.activity_id and mine.user_id = to_user
    );
  get diagnostics dropped = row_count;

  update public.rsvps as r
  set user_id = to_user
  where r.user_id = from_user;
  get diagnostics moved = row_count;

  perform private.audit(
    'data_fix',
    'profile',
    from_user,
    why,
    jsonb_build_object(
      'transferred_to', to_user,
      'activities', organized,
      'rsvps_moved', moved,
      'rsvps_dropped', dropped
    )
  );
end;
$$;
