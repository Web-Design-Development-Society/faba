-- Group updates (GRP-04). Design document sections 8.7, 8.8 and 8.10, and FR-GRP-3. A group's
-- organizers post one-way updates to its members, with the same rules as an activity's (NOTIF-04):
-- up to 500 characters, and reportable. A group takes at most 3 in 24 hours. They're kept with
-- activities' updates, each row belonging to an activity or a group, so reporting, hiding (MOD-03),
-- the reports queue and Alerts work for both.

ALTER TABLE public.activity_updates
ALTER COLUMN activity_id DROP NOT NULL,
ADD COLUMN group_id uuid REFERENCES public.groups (id)
  ON DELETE CASCADE,
ADD CONSTRAINT activity_updates_one_place_check CHECK ((activity_id IS NULL) != (group_id IS NULL));

-- The group's page shows them newest first.
CREATE INDEX activity_updates_group_idx ON public.activity_updates (group_id, created_at DESC);

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
      'group_update'
    )
  );

-- Members read updates as before (20261110130000_report_and_hide_updates.sql): to the activities
-- they can see, or to the groups they're in. Moderators read a group's too.
DROP POLICY "Active members read updates to the activities they can see" ON public.activity_updates;

CREATE POLICY "Active members read updates to the activities and groups they can see" ON public.activity_updates
FOR SELECT
TO authenticated
USING (
  (SELECT private.is_active_member())
  AND (
    hidden_at IS NULL
    OR author_id = (SELECT auth.uid())
    OR (SELECT private.is_moderator()) IS TRUE
  )
  AND (
    EXISTS (
      SELECT
      FROM public.activities AS a
      WHERE a.id = activity_updates.activity_id
    )
    OR group_id IS NOT NULL
    AND (private.is_group_member(group_id) OR (SELECT private.is_moderator()) IS TRUE)
  )
);

-- Posts an update to group `group_id`, which tells its other active members. Only its owner and
-- organizers can, while it isn't archived or hidden. Posting again with the same idempotency key
-- returns the update already posted. Returns its id.
CREATE FUNCTION public.post_group_update(
  group_id uuid,
  body text,
  idempotency_key uuid DEFAULT NULL
)
RETURNS uuid
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
declare
  g public.groups;
  posted text := btrim(post_group_update.body, E' \t\r\n');
  new_id uuid;
  told uuid[];
begin
  if not private.is_active_member() then
    raise exception 'NOT_ACTIVE' using errcode = '42501';
  end if;

  -- Locked, so updates to one group count one at a time.
  select * into g from public.groups as x where x.id = post_group_update.group_id for update;

  -- The same for a group that doesn't exist, so nobody learns which ones do.
  if not found or not exists (
    select from public.group_members as m
    where
      m.group_id = g.id
      and m.user_id = auth.uid()
      and m.role in ('owner', 'organizer')
      and m.status = 'active'
  ) then
    raise exception 'NOT_GROUP_ORGANIZER' using errcode = '42501';
  end if;

  if post_group_update.idempotency_key is not null then
    select u.id into new_id
    from public.activity_updates as u
    where u.author_id = auth.uid() and u.idempotency_key = post_group_update.idempotency_key;

    if found then
      return new_id;
    end if;
  end if;

  if g.hidden_at is not null or g.archived_at is not null then
    raise exception 'GROUP_ARCHIVED' using errcode = '22023';
  end if;

  if posted is null or char_length(posted) not between 1 and 500 then
    raise exception 'INVALID_BODY' using errcode = '22023';
  end if;

  -- At most 3 to a group in 24 hours, hidden ones included (GRP-04).
  if (
    select count(*)
    from public.activity_updates as u
    where u.group_id = g.id and u.created_at > now() - interval '24 hours'
  ) >= 3 then
    raise exception 'GROUP_UPDATE_QUOTA_EXCEEDED' using errcode = 'P0001';
  end if;

  insert into public.activity_updates (group_id, author_id, body, idempotency_key)
  values (g.id, auth.uid(), posted, post_group_update.idempotency_key)
  returning id into new_id;

  told := array(
      select m.user_id
      from public.group_members as m
      join public.profiles as p on p.id = m.user_id
      where
        m.group_id = g.id
        and m.status = 'active'
        and m.user_id != auth.uid()
        and p.status = 'active'
    );

  perform private.notify(
    told,
    'group_update',
    null,
    jsonb_build_object('update_id', new_id, 'name', g.name)
  );

  -- Each one's group, for Alerts to name and open.
  update public.notifications as n
  set group_id = g.id
  where
    n.recipient_id = any(told)
    and n.created_at = now()
    and n.type = 'group_update'
    and n.payload ->> 'update_id' = new_id::text;

  return new_id;
end;
$$;

GRANT EXECUTE ON FUNCTION public.post_group_update(uuid, text, uuid) TO authenticated;

-- Reporting as before (20261110130000_report_and_hide_updates.sql), with updates to groups.
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
    -- An update to an activity, or to a group (GRP-04), when neither it nor where it was posted is
    -- hidden.
    select u.author_id into owner
    from public.activity_updates as u
    left join public.activities as a on a.id = u.activity_id
    left join public.groups as g on g.id = u.group_id
    where
      u.id = report_content.target_id
      and u.hidden_at is null
      and a.hidden_at is null
      and g.hidden_at is null;
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
