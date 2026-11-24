-- A picture's space before it loads (MEDIA-04). Each picture keeps its width and height, as it
-- shows, which the Worker reads from the file when it's added (src/lib/media.ts). The page gives an
-- activity's cover its shape before it loads, so the page doesn't move. A picture added before this
-- has no size, and the page keeps a 16:9 space for it until it loads, as before.

ALTER TABLE public.images
ADD COLUMN width INTEGER CHECK (width BETWEEN 1 AND 65535),
ADD COLUMN height INTEGER CHECK (height BETWEEN 1 AND 65535),
-- Both or neither.
ADD CONSTRAINT images_size_whole CHECK ((width IS NULL) = (height IS NULL));

-- The functions that add a picture take its size too. It's last and can be left out, so the Worker
-- from before this still works while it's deployed. Otherwise they're the same as before
-- (20261115120000_images.sql and 20261115160000_profile_photos.sql).
DROP FUNCTION public.set_activity_cover(uuid, text, text, INTEGER, text);
DROP FUNCTION public.set_group_banner(uuid, text, text, INTEGER, text);
DROP FUNCTION public.set_profile_photo(text, text, INTEGER);

-- Sets an activity's cover to a file the Worker stored. The organizer or a co-organizer can, on an
-- activity that isn't hidden. Returns the image's id. The old image stays on record, so reports on
-- it still work.
CREATE FUNCTION public.set_activity_cover(
  activity_id uuid,
  r2_key text,
  content_type text,
  bytes INTEGER,
  alt text,
  width INTEGER DEFAULT NULL,
  height INTEGER DEFAULT NULL
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

  insert into public.images (
    r2_key, content_type, bytes, alt, width, height, activity_id, uploaded_by
  )
  values (
    set_activity_cover.r2_key,
    set_activity_cover.content_type,
    set_activity_cover.bytes,
    trim(set_activity_cover.alt),
    set_activity_cover.width,
    set_activity_cover.height,
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
ON FUNCTION public.set_activity_cover(uuid, text, text, INTEGER, text, INTEGER, INTEGER)
FROM PUBLIC, anon;
GRANT EXECUTE
ON FUNCTION public.set_activity_cover(uuid, text, text, INTEGER, text, INTEGER, INTEGER)
TO authenticated;

-- Sets a group's banner, for its owner or an organizer of it. Returns the image's id.
CREATE FUNCTION public.set_group_banner(
  group_id uuid,
  r2_key text,
  content_type text,
  bytes INTEGER,
  alt text,
  width INTEGER DEFAULT NULL,
  height INTEGER DEFAULT NULL
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

  insert into public.images (r2_key, content_type, bytes, alt, width, height, group_id, uploaded_by)
  values (
    set_group_banner.r2_key,
    set_group_banner.content_type,
    set_group_banner.bytes,
    trim(set_group_banner.alt),
    set_group_banner.width,
    set_group_banner.height,
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
ON FUNCTION public.set_group_banner(uuid, text, text, INTEGER, text, INTEGER, INTEGER)
FROM PUBLIC, anon;
GRANT EXECUTE
ON FUNCTION public.set_group_banner(uuid, text, text, INTEGER, text, INTEGER, INTEGER)
TO authenticated;

-- Sets the signed-in member's photo to a file the Worker stored, and shows it. Its description is
-- the member's name, as for any face. Returns the R2 key of the photo it replaced, for the Worker to
-- delete, or null.
CREATE FUNCTION public.set_profile_photo(
  r2_key text,
  content_type text,
  bytes INTEGER,
  width INTEGER DEFAULT NULL,
  height INTEGER DEFAULT NULL
)
RETURNS text
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
declare
  me public.profiles;
  old_key text;
  image_id uuid;
begin
  if not private.is_active_member() then
    raise exception 'NOT_ACTIVE' using errcode = '42501';
  end if;

  select * into me from public.profiles as p where p.id = auth.uid() for update;
  select i.r2_key into old_key from public.images as i where i.id = me.photo_image_id;

  insert into public.images (r2_key, content_type, bytes, alt, width, height, profile_id, uploaded_by)
  values (
    set_profile_photo.r2_key,
    set_profile_photo.content_type,
    set_profile_photo.bytes,
    me.display_name,
    set_profile_photo.width,
    set_profile_photo.height,
    me.id,
    me.id
  )
  returning id into image_id;

  update public.profiles as p
  set photo_image_id = image_id, use_initials = false
  where p.id = me.id;

  delete from public.images as i where i.id = me.photo_image_id;
  perform private.refresh_avatar(me.id);
  return old_key;
end;
$$;

REVOKE EXECUTE
ON FUNCTION public.set_profile_photo(text, text, INTEGER, INTEGER, INTEGER)
FROM PUBLIC, anon;
GRANT EXECUTE
ON FUNCTION public.set_profile_photo(text, text, INTEGER, INTEGER, INTEGER)
TO authenticated;
