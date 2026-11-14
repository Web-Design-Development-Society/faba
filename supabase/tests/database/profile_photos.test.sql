-- Profile photos (UI-11): setting, replacing and removing one, who reads it, and a moderator hiding
-- it. Run with `npm run db:test`.
BEGIN;

CREATE EXTENSION IF NOT EXISTS pgtap WITH SCHEMA extensions;

SELECT plan(16);

-- Pia has a Google photo, Gil has none, and Mo is a moderator.
INSERT INTO auth.users
  (id, email, raw_user_meta_data)
VALUES
  (
    'c0000000-0000-4000-8000-000000000391',
    'pia@byui.edu',
    '{"full_name": "Pia Photo", "avatar_url": "https://lh3.example.com/pia.jpg"}'
  ),
  ('c0000000-0000-4000-8000-000000000392', 'gil@byui.edu', '{"full_name": "Gil Guest"}'),
  ('c0000000-0000-4000-8000-000000000393', 'mo@byui.edu', '{"full_name": "Mo Moderator"}');

UPDATE public.profiles
SET
  guidelines_version = 1,
  guidelines_accepted_at = now(),
  role = CASE id WHEN 'c0000000-0000-4000-8000-000000000393' THEN 'moderator' ELSE 'member' END
WHERE id::text LIKE 'c0000000-0000-4000-8000-00000000039_';

SELECT ok(
  (
    (
      SELECT google_avatar_url
      FROM public.profiles
      WHERE id = 'c0000000-0000-4000-8000-000000000391'
    )
  ) IS NOT DISTINCT FROM ('https://lh3.example.com/pia.jpg'),
  'a new profile keeps the photo Google gave'
);

CREATE FUNCTION pg_temp.as_member(n INTEGER)
RETURNS void
LANGUAGE sql
AS $$
  SELECT set_config(
    'request.jwt.claims',
    jsonb_build_object(
      'sub',
      'c0000000-0000-4000-8000-00000000039' || n,
      'email',
      'm@byui.edu'
    )::text,
    TRUE
  );
$$;

CREATE FUNCTION pg_temp.avatar(n INTEGER)
RETURNS text
LANGUAGE sql
SECURITY DEFINER
AS $$
  SELECT avatar_url
  FROM public.profiles
  WHERE id::text = 'c0000000-0000-4000-8000-00000000039' || n;
$$;

GRANT EXECUTE ON ALL FUNCTIONS IN SCHEMA pg_temp TO authenticated;

SET LOCAL ROLE authenticated;

SELECT pg_temp.as_member(1);

SELECT ok(
  (public.set_profile_photo('profiles/pia-1', 'image/jpeg', 50000)) IS NOT DISTINCT FROM (NULL),
  'a first photo replaces nothing'
);

SELECT matches(
  pg_temp.avatar(1),
  '^/api/media/[0-9a-f-]{36}\?size=thumb$',
  'the uploaded photo shows in place of Google''s'
);

SELECT ok(
  ((SELECT alt FROM public.images WHERE r2_key = 'profiles/pia-1')) IS NOT DISTINCT FROM (
    'Pia Photo'
  ),
  'its description is the member''s name'
);

SELECT ok(
  (public.set_profile_photo('profiles/pia-2', 'image/jpeg', 60000)) IS NOT DISTINCT FROM (
    'profiles/pia-1'
  ),
  'a new photo returns the old one''s key, for the Worker to delete'
);

SELECT ok(
  (
    (SELECT count(*)::INTEGER FROM public.images WHERE r2_key = 'profiles/pia-1')
  ) IS NOT DISTINCT FROM (0),
  'and the old photo''s row is gone'
);

SELECT pg_temp.as_member(2);

SELECT ok(
  (
    (SELECT count(*)::INTEGER FROM public.images WHERE r2_key = 'profiles/pia-2')
  ) IS NOT DISTINCT FROM (1),
  'another member reads the photo, so it can be served'
);

SELECT ok(
  (pg_temp.avatar(2)) IS NOT DISTINCT FROM (NULL),
  'a member with no Google photo and no upload shows initials'
);

SELECT pg_temp.as_member(1);

SELECT throws_ok(
  $$update public.profiles set avatar_url = 'https://evil.example.com/x.png'
    where id = 'c0000000-0000-4000-8000-000000000391'$$,
  '42501',
  NULL,
  'a member can''t point their face anywhere they like'
);

-- Gil reports Pia's photo, and Mo hides it.
SELECT pg_temp.as_member(2);

SELECT lives_ok(
  $$select public.report_content(
    'image', (select id from public.images where r2_key = 'profiles/pia-2'), 'inappropriate'
  )$$,
  'a profile photo can be reported'
);

SELECT pg_temp.as_member(3);

SELECT lives_ok(
  $$select public.moderate_hide_image(
    (select id from public.images where r2_key = 'profiles/pia-2'), 'Not a photo of a person'
  )$$,
  'a moderator hides a profile photo'
);

SELECT ok((pg_temp.avatar(1)) IS NOT DISTINCT FROM (NULL), 'a hidden photo shows initials');

SELECT lives_ok(
  $$select public.moderate_unhide_image(
    (select id from public.images where r2_key = 'profiles/pia-2'), 'Reviewed again'
  )$$,
  'and unhides it'
);

SELECT matches(pg_temp.avatar(1), '^/api/media/', 'which shows it again');

SELECT pg_temp.as_member(1);

SELECT ok(
  (public.remove_profile_photo()) IS NOT DISTINCT FROM ('profiles/pia-2'),
  'removing the photo returns its key, for the Worker to delete'
);

SELECT ok(
  (pg_temp.avatar(1)) IS NOT DISTINCT FROM ('https://lh3.example.com/pia.jpg'),
  'and Google''s photo shows again'
);

SELECT * FROM finish();

ROLLBACK;
