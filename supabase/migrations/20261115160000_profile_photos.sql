-- Profile photos (UI-11). A member can upload their own photo, which shows wherever their face does,
-- in place of the photo Google gave them. The file is in the R2 bucket like other pictures
-- (MEDIA-01), and its images row says whose profile it's for. profiles.avatar_url, which every face
-- already reads, points at whichever photo shows: the uploaded one, served by /api/media, or
-- Google's. A photo a moderator hides shows initials (avatar_url is null) until it's unhidden or
-- replaced. Replacing or removing a photo deletes its row, and the Worker deletes its files, so a
-- member's old photos aren't kept.

-- The photo Google gave, kept apart so removing an uploaded one goes back to it. Today avatar_url is
-- always Google's.
ALTER TABLE public.profiles ADD COLUMN google_avatar_url text;

UPDATE public.profiles SET google_avatar_url = avatar_url;

-- New profiles keep Google's photo too. handle_new_user() sets avatar_url from Google.
CREATE FUNCTION private.keep_google_avatar()
RETURNS trigger
LANGUAGE plpgsql
SET search_path = ''
AS $$
begin
  new.google_avatar_url := coalesce(new.google_avatar_url, new.avatar_url);
  return new;
end;
$$;

CREATE TRIGGER profiles_keep_google_avatar
BEFORE INSERT ON public.profiles
FOR EACH ROW
EXECUTE FUNCTION private.keep_google_avatar();

-- An image belongs to exactly one activity, group or profile. A member's photos go with their
-- account (PROF-05).
ALTER TABLE public.images
ADD COLUMN profile_id uuid REFERENCES public.profiles (id)
  ON DELETE CASCADE;

ALTER TABLE public.images DROP CONSTRAINT images_check;

ALTER TABLE public.images
ADD CONSTRAINT images_one_owner CHECK (num_nonnulls(activity_id, group_id, profile_id) = 1);

ALTER TABLE public.profiles
ADD COLUMN photo_image_id uuid REFERENCES public.images (id)
  ON DELETE SET NULL;

-- Members read a profile's photo when they can read the profile, as for activities and groups.
DROP POLICY "Active members read images they can see" ON public.images;

CREATE POLICY "Active members read images they can see" ON public.images
FOR SELECT
TO authenticated
USING (
  (SELECT private.is_active_member())
  AND (images.hidden_at IS NULL OR (SELECT private.is_moderator()))
  AND (
    EXISTS (SELECT FROM public.activities AS a WHERE a.id = images.activity_id)
    OR EXISTS (SELECT FROM public.groups AS g WHERE g.id = images.group_id)
    OR EXISTS (SELECT FROM public.profiles AS p WHERE p.id = images.profile_id)
  )
);

-- Points a profile's avatar_url at the photo that shows: its uploaded photo, served small by
-- /api/media, nothing while a moderator has hidden that, or Google's when it has none.
CREATE FUNCTION private.refresh_avatar(profile_id uuid)
RETURNS void
LANGUAGE sql
SECURITY DEFINER
SET search_path = ''
AS $$
  UPDATE public.profiles AS p
  SET avatar_url = CASE
    WHEN p.photo_image_id IS NULL THEN p.google_avatar_url
    WHEN
      EXISTS (SELECT FROM public.images AS i WHERE i.id = p.photo_image_id AND i.hidden_at IS NULL)
    THEN
      '/api/media/' || p.photo_image_id || '?size=thumb'
  END
  WHERE p.id = refresh_avatar.profile_id;
$$;

-- When a moderator hides or unhides a profile photo (MOD-08), the faces follow.
CREATE FUNCTION private.refresh_avatar_after_moderation()
RETURNS trigger
LANGUAGE plpgsql
SET search_path = ''
AS $$
begin
  if new.profile_id is not null then
    perform private.refresh_avatar(new.profile_id);
  end if;
  return null;
end;
$$;

CREATE TRIGGER images_refresh_avatar
AFTER UPDATE OF hidden_at ON public.images
FOR EACH ROW
EXECUTE FUNCTION private.refresh_avatar_after_moderation();

-- Sets the signed-in member's photo to a file the Worker stored, and shows it. Its description is
-- the member's name, as for any face. Returns the R2 key of the photo it replaced, for the Worker to
-- delete, or null.
CREATE FUNCTION public.set_profile_photo(r2_key text, content_type text, bytes INTEGER)
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

  insert into public.images (r2_key, content_type, bytes, alt, profile_id, uploaded_by)
  values (
    set_profile_photo.r2_key,
    set_profile_photo.content_type,
    set_profile_photo.bytes,
    me.display_name,
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

REVOKE EXECUTE ON FUNCTION public.set_profile_photo(text, text, INTEGER) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.set_profile_photo(text, text, INTEGER) TO authenticated;

-- Removes the signed-in member's photo, which goes back to Google's photo or initials. Returns its
-- R2 key, for the Worker to delete, or null when there was none. Any member can, even one who's
-- suspended or no longer eligible, since it only takes something away.
CREATE FUNCTION public.remove_profile_photo()
RETURNS text
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
declare
  me public.profiles;
  old_key text;
begin
  select * into me from public.profiles as p where p.id = auth.uid() for update;
  if me.photo_image_id is null then
    return null;
  end if;

  select i.r2_key into old_key from public.images as i where i.id = me.photo_image_id;
  update public.profiles as p set photo_image_id = null where p.id = me.id;
  delete from public.images as i where i.id = me.photo_image_id;
  perform private.refresh_avatar(me.id);
  return old_key;
end;
$$;

REVOKE EXECUTE ON FUNCTION public.remove_profile_photo() FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.remove_profile_photo() TO authenticated;
