-- Images for activities and groups (MEDIA-01). Files live in an R2 bucket, which the Worker reads and
-- writes through a binding. The database keeps what they're for, who uploaded them and whether a
-- moderator hid them. The Worker checks the file, stores it under a random key, then calls
-- set_activity_cover() or set_group_banner(), which point the activity or group at it. Images are
-- served only when the signed-in member can see the activity or group, and hidden ones never are.
-- Images are reportable, and moderators can hide them with a reason, as for comments.

CREATE TABLE public.images (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  -- A random key in the R2 bucket, chosen by the Worker. Unique, so a key points to one image.
  r2_key text NOT NULL UNIQUE CHECK (char_length(r2_key) BETWEEN 1 AND 200),
  content_type text NOT NULL CHECK (content_type IN ('image/jpeg', 'image/png', 'image/webp')),
  -- The Worker refuses anything over 2 MB, and this checks it again.
  bytes INTEGER NOT NULL CHECK (bytes BETWEEN 1 AND 2097152),
  -- A description for screen readers, which the form requires.
  alt text NOT NULL CHECK (char_length(trim(alt)) BETWEEN 1 AND 200),
  activity_id uuid REFERENCES public.activities (id)
    ON DELETE CASCADE,
  group_id uuid REFERENCES public.groups (id)
    ON DELETE CASCADE,
  uploaded_by uuid REFERENCES public.profiles (id)
    ON DELETE SET NULL,
  created_at timestamptz NOT NULL DEFAULT now(),
  hidden_at timestamptz,
  hidden_reason text CHECK (char_length(hidden_reason) <= 500),
  hidden_by uuid REFERENCES public.profiles (id)
    ON DELETE SET NULL,
  -- An image belongs to an activity or a group, never both.
  CHECK ((activity_id IS NULL) != (group_id IS NULL))
);

ALTER TABLE public.images ENABLE ROW LEVEL SECURITY;

ALTER TABLE public.activities
ADD COLUMN cover_image_id uuid REFERENCES public.images (id)
  ON DELETE SET NULL;

ALTER TABLE public.groups
ADD COLUMN banner_image_id uuid REFERENCES public.images (id)
  ON DELETE SET NULL;

-- Members read the images of activities and groups they can see, unless the image is hidden.
-- Moderators read hidden ones too. The same as for updates and comments.
CREATE POLICY "Active members read images they can see" ON public.images
FOR SELECT
TO authenticated
USING (
  (SELECT private.is_active_member())
  AND (images.hidden_at IS NULL OR (SELECT private.is_moderator()))
  AND (
    EXISTS (SELECT FROM public.activities AS a WHERE a.id = images.activity_id)
    OR EXISTS (SELECT FROM public.groups AS g WHERE g.id = images.group_id)
  )
);

-- Sets an activity's cover to a file the Worker stored. The organizer or a co-organizer can, on an
-- activity that isn't hidden. Returns the image's id. The old image stays on record, so reports on
-- it still work.
CREATE FUNCTION public.set_activity_cover(
  activity_id uuid,
  r2_key text,
  content_type text,
  bytes INTEGER,
  alt text
)
RETURNS uuid
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
declare
  activity public.activities;
  image_id uuid;
begin
  if not private.is_active_member() then
    raise exception 'NOT_ACTIVE' using errcode = '42501';
  end if;

  select * into activity
  from public.activities as a
  where a.id = set_activity_cover.activity_id and a.hidden_at is null
  for update;

  if not found then
    raise exception 'ACTIVITY_NOT_FOUND' using errcode = 'P0002';
  end if;

  if activity.organizer_id is distinct from auth.uid() and not exists (
    select from public.activity_co_organizers as c
    where c.activity_id = activity.id and c.user_id = auth.uid()
  ) then
    raise exception 'NOT_ORGANIZER' using errcode = '42501';
  end if;

  insert into public.images (r2_key, content_type, bytes, alt, activity_id, uploaded_by)
  values (
    set_activity_cover.r2_key,
    set_activity_cover.content_type,
    set_activity_cover.bytes,
    trim(set_activity_cover.alt),
    activity.id,
    auth.uid()
  )
  returning id into image_id;

  update public.activities as a
  set cover_image_id = image_id
  where a.id = activity.id;

  return image_id;
end;
$$;

REVOKE EXECUTE
ON FUNCTION public.set_activity_cover(uuid, text, text, INTEGER, text)
FROM PUBLIC, anon;
GRANT EXECUTE
ON FUNCTION public.set_activity_cover(uuid, text, text, INTEGER, text)
TO authenticated;

-- Sets a group's banner, for its owner or an organizer of it. Returns the image's id.
CREATE FUNCTION public.set_group_banner(
  group_id uuid,
  r2_key text,
  content_type text,
  bytes INTEGER,
  alt text
)
RETURNS uuid
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
declare
  managed public.groups;
  managed_role text;
  image_id uuid;
begin
  select g.* into managed
  from public.groups as g
  where g.id = set_group_banner.group_id and g.hidden_at is null;

  if not found then
    raise exception 'GROUP_NOT_FOUND' using errcode = 'P0002';
  end if;

  if not private.is_active_member() then
    raise exception 'NOT_ACTIVE' using errcode = '42501';
  end if;

  select m.role into managed_role
  from public.group_members as m
  where m.group_id = managed.id and m.user_id = auth.uid() and m.status = 'active';

  if managed_role is null or managed_role not in ('owner', 'organizer') then
    raise exception 'NOT_GROUP_ORGANIZER' using errcode = '42501';
  end if;

  insert into public.images (r2_key, content_type, bytes, alt, group_id, uploaded_by)
  values (
    set_group_banner.r2_key,
    set_group_banner.content_type,
    set_group_banner.bytes,
    trim(set_group_banner.alt),
    managed.id,
    auth.uid()
  )
  returning id into image_id;

  update public.groups as g
  set banner_image_id = image_id
  where g.id = managed.id;

  return image_id;
end;
$$;

REVOKE EXECUTE
ON FUNCTION public.set_group_banner(uuid, text, text, INTEGER, text)
FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.set_group_banner(uuid, text, text, INTEGER, text) TO authenticated;

-- Hiding and unhiding an image (MEDIA-01), with a reason for the audit log. Hiding deals with its
-- open reports, as it does for comments and updates.
CREATE FUNCTION public.moderate_hide_image(image_id uuid, reason text)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
declare
  posted public.images;
  why text := nullif(trim(moderate_hide_image.reason), '');
  actioned integer;
begin
  if not private.is_moderator() then
    raise exception 'NOT_MODERATOR' using errcode = '42501';
  end if;

  if why is null then
    raise exception 'REASON_REQUIRED' using errcode = '22023';
  end if;

  select * into posted
  from public.images as i
  where i.id = moderate_hide_image.image_id
  for update;

  if not found then
    raise exception 'IMAGE_NOT_FOUND' using errcode = 'P0002';
  end if;

  if posted.hidden_at is not null then
    raise exception 'IMAGE_ALREADY_HIDDEN' using errcode = '22023';
  end if;

  update public.images as i
  set hidden_at = now(), hidden_reason = why, hidden_by = auth.uid()
  where i.id = posted.id;

  update public.reports as r
  set status = 'actioned', resolved_by = auth.uid(), resolved_at = now(), resolution_note = why
  where r.target_type = 'image' and r.target_id = posted.id and r.status = 'open';
  get diagnostics actioned = row_count;

  perform private.audit(
    'hide',
    'image',
    posted.id,
    why,
    jsonb_build_object(
      'activity_id', posted.activity_id,
      'group_id', posted.group_id,
      'reports_actioned', actioned
    )
  );
end;
$$;

REVOKE EXECUTE ON FUNCTION public.moderate_hide_image(uuid, text) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.moderate_hide_image(uuid, text) TO authenticated;

CREATE FUNCTION public.moderate_unhide_image(image_id uuid, reason text)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
declare
  posted public.images;
  why text := nullif(trim(moderate_unhide_image.reason), '');
begin
  if not private.is_moderator() then
    raise exception 'NOT_MODERATOR' using errcode = '42501';
  end if;

  if why is null then
    raise exception 'REASON_REQUIRED' using errcode = '22023';
  end if;

  select * into posted
  from public.images as i
  where i.id = moderate_unhide_image.image_id
  for update;

  if not found then
    raise exception 'IMAGE_NOT_FOUND' using errcode = 'P0002';
  end if;

  if posted.hidden_at is null then
    raise exception 'IMAGE_NOT_HIDDEN' using errcode = '22023';
  end if;

  update public.images as i
  set hidden_at = null, hidden_reason = null, hidden_by = null
  where i.id = posted.id;

  perform private.audit(
    'unhide',
    'image',
    posted.id,
    why,
    jsonb_build_object('activity_id', posted.activity_id, 'group_id', posted.group_id)
  );
end;
$$;

REVOKE EXECUTE ON FUNCTION public.moderate_unhide_image(uuid, text) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.moderate_unhide_image(uuid, text) TO authenticated;

-- Images can be reported, like comments.
ALTER TABLE public.reports DROP CONSTRAINT reports_target_type_check;
ALTER TABLE public.reports
ADD CONSTRAINT reports_target_type_check
  CHECK (target_type IN ('activity', 'profile', 'activity_update', 'group', 'comment', 'image'));

-- The audit log names images as targets, and keeps the types it already has.
ALTER TABLE private.audit_log DROP CONSTRAINT audit_log_target_type_check;
ALTER TABLE private.audit_log
ADD CONSTRAINT audit_log_target_type_check
  CHECK (
    target_type IN (
      'activity',
      'profile',
      'report',
      'activity_update',
      'group',
      'comment',
      'league_game',
      'image'
    )
  );

CREATE OR REPLACE FUNCTION public.report_content(
  target_type text,
  target_id uuid,
  reason text,
  note text DEFAULT NULL::text
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
  elsif report_content.target_type = 'group' then
    -- A group that isn't hidden (MOD-08). Its owner can't report it.
    select g.owner_id into owner
    from public.groups as g
    where g.id = report_content.target_id and g.hidden_at is null;
  elsif report_content.target_type = 'comment' then
    -- A comment that isn't hidden, on an activity that isn't (ACT-12).
    select c.author_id into owner
    from public.activity_comments as c
    join public.activities as a on a.id = c.activity_id
    where
      c.id = report_content.target_id
      and c.hidden_at is null
      and a.hidden_at is null;
  elsif report_content.target_type = 'image' then
    -- An image that isn't hidden, on an activity or a group that isn't (MEDIA-01). Its uploader
    -- can't report it.
    select i.uploaded_by into owner
    from public.images as i
    left join public.activities as a on a.id = i.activity_id
    left join public.groups as g on g.id = i.group_id
    where
      i.id = report_content.target_id
      and i.hidden_at is null
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

  perform private.notify(
    array(
      select p.id
      from public.profiles as p
      where p.role in ('moderator', 'admin') and p.status = 'active' and p.id <> auth.uid()
    ),
    'report_received',
    null,
    jsonb_build_object('kind', report_content.target_type, 'href', '/mod'),
    'report-received:' || report_id
  );

  return report_id;
end;
$$;
