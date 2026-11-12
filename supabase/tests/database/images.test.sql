-- Images for activities and groups, and reporting and hiding them (MEDIA-01). Run with
-- `npm run db:test`.
BEGIN;

CREATE EXTENSION IF NOT EXISTS pgtap WITH SCHEMA extensions;

SELECT plan(19);

-- Otto organizes a hike and runs a group. Gwen is a member of the group, and can't change its
-- pictures. Gwen reports Otto's cover, and Mo, a moderator, hides it.
INSERT INTO auth.users
  (id, email, raw_user_meta_data)
SELECT
  ('c0000000-0000-4000-8000-00000000035' || n)::uuid,
  name || '@byui.edu',
  jsonb_build_object('full_name', name)
FROM (
  VALUES
    (1, 'otto'),
    (2, 'gwen'),
    (3, 'mo')
) AS v (n, name);

UPDATE public.profiles
SET
  guidelines_version = 1,
  guidelines_accepted_at = now(),
  role = CASE id WHEN 'c0000000-0000-4000-8000-000000000353' THEN 'moderator' ELSE 'member' END
WHERE id::text LIKE 'c0000000-0000-4000-8000-00000000035_';

INSERT INTO public.groups
  (id, slug, name, category_id, join_policy, owner_id)
VALUES
  (
    'b0000000-0000-4000-8000-000000000351',
    'hikers-351',
    'Hikers',
    'outdoors',
    'open',
    'c0000000-0000-4000-8000-000000000351'
  );

INSERT INTO public.group_members
  (group_id, user_id, role)
VALUES
  ('b0000000-0000-4000-8000-000000000351', 'c0000000-0000-4000-8000-000000000351', 'owner'),
  ('b0000000-0000-4000-8000-000000000351', 'c0000000-0000-4000-8000-000000000352', 'member');

INSERT INTO public.activities
  (id, organizer_id, category_id, title, starts_at, location_name, hidden_at)
VALUES
  (
    'f0000000-0000-4000-8000-000000000351',
    'c0000000-0000-4000-8000-000000000351',
    'outdoors',
    'Hike',
    now() + INTERVAL '1 day',
    'R Mountain trailhead',
    NULL
  ),
  (
    'f0000000-0000-4000-8000-000000000352',
    'c0000000-0000-4000-8000-000000000351',
    'outdoors',
    'Hidden hike',
    now() + INTERVAL '2 days',
    'R Mountain trailhead',
    now()
  );

CREATE FUNCTION pg_temp.as_member(n INTEGER)
RETURNS void
LANGUAGE sql
AS $$
  SELECT set_config(
    'request.jwt.claims',
    jsonb_build_object(
      'sub',
      'c0000000-0000-4000-8000-00000000035' || n,
      'email',
      'm@byui.edu'
    )::text,
    TRUE
  );
$$;

GRANT EXECUTE ON ALL FUNCTIONS IN SCHEMA pg_temp TO authenticated;

SET LOCAL ROLE authenticated;

SELECT pg_temp.as_member(1);

SELECT lives_ok(
  $$select public.set_activity_cover(
    'f0000000-0000-4000-8000-000000000351', 'activities/cover-1', 'image/jpeg', 120000,
    'A trail through pines'
  )$$,
  'an organizer sets an activity''s cover'
);

SELECT pg_temp.as_member(2);

SELECT throws_ok(
  $$select public.set_activity_cover(
    'f0000000-0000-4000-8000-000000000351', 'activities/cover-x', 'image/jpeg', 120000, 'Nope'
  )$$,
  '42501',
  'NOT_ORGANIZER',
  'a member can''t set an activity''s cover'
);

SELECT pg_temp.as_member(1);

SELECT throws_ok(
  $$select public.set_activity_cover(
    'f0000000-0000-4000-8000-000000000351', 'activities/cover-2', 'image/gif', 120000, 'A gif'
  )$$,
  '23514',
  NULL,
  'only JPEG, PNG and WebP are stored'
);

SELECT throws_ok(
  $$select public.set_activity_cover(
    'f0000000-0000-4000-8000-000000000351', 'activities/cover-3', 'image/jpeg', 3000000, 'Big'
  )$$,
  '23514',
  NULL,
  'a file over 2 MB is refused'
);

SELECT throws_ok(
  $$select public.set_activity_cover(
    'f0000000-0000-4000-8000-000000000352', 'activities/cover-4', 'image/jpeg', 1000, 'Hidden'
  )$$,
  'P0002',
  'ACTIVITY_NOT_FOUND',
  'nobody sets the cover of a hidden activity'
);

SELECT results_eq(
  $$select count(*) from public.activities where cover_image_id is not null$$,
  $$values (1::bigint)$$,
  'the activity points at its new cover'
);

SELECT lives_ok(
  $$select public.set_group_banner(
    'b0000000-0000-4000-8000-000000000351', 'groups/banner-1', 'image/png', 90000, 'Hikers on a ridge'
  )$$,
  'a group owner sets the banner'
);

SELECT pg_temp.as_member(2);

SELECT throws_ok(
  $$select public.set_group_banner(
    'b0000000-0000-4000-8000-000000000351', 'groups/banner-2', 'image/png', 90000, 'Nope'
  )$$,
  '42501',
  'NOT_GROUP_ORGANIZER',
  'a member of the group can''t set its banner'
);

SELECT results_eq(
  $$select count(*) from public.images
  where activity_id = 'f0000000-0000-4000-8000-000000000351'$$,
  $$values (1::bigint)$$,
  'members read the images of the activities they can see'
);

SELECT lives_ok(
  $$select public.report_content(
    'image',
    (select cover_image_id from public.activities where id = 'f0000000-0000-4000-8000-000000000351'),
    'inappropriate'
  )$$,
  'a member reports an image'
);

SELECT throws_ok(
  $$select public.report_content(
    'image',
    (select cover_image_id from public.activities where id = 'f0000000-0000-4000-8000-000000000351'),
    'spam'
  )$$,
  '23505',
  'ALREADY_REPORTED',
  'an image is reported once by each member'
);

SELECT pg_temp.as_member(1);

SELECT throws_ok(
  $$select public.report_content(
    'image',
    (select cover_image_id from public.activities where id = 'f0000000-0000-4000-8000-000000000351'),
    'spam'
  )$$,
  '22023',
  'REPORT_OWN',
  'nobody reports their own image'
);

SELECT pg_temp.as_member(2);

SELECT throws_ok(
  $$select public.moderate_hide_image(
    (select cover_image_id from public.activities where id = 'f0000000-0000-4000-8000-000000000351'),
    'Spam'
  )$$,
  '42501',
  'NOT_MODERATOR',
  'members can''t hide an image'
);

SELECT pg_temp.as_member(3);

SELECT throws_ok(
  $$select public.moderate_hide_image(
    (select cover_image_id from public.activities where id = 'f0000000-0000-4000-8000-000000000351'),
    ' '
  )$$,
  '22023',
  'REASON_REQUIRED',
  'hiding an image needs a reason'
);

SELECT lives_ok(
  $$select public.moderate_hide_image(
    (select cover_image_id from public.activities where id = 'f0000000-0000-4000-8000-000000000351'),
    'Spam'
  )$$,
  'a moderator hides an image'
);

SELECT throws_ok(
  $$select public.moderate_hide_image(
    (select cover_image_id from public.activities where id = 'f0000000-0000-4000-8000-000000000351'),
    'Spam'
  )$$,
  '22023',
  'IMAGE_ALREADY_HIDDEN',
  'an image is hidden once'
);

SELECT results_eq(
  $$select hidden_reason from public.images
  where activity_id = 'f0000000-0000-4000-8000-000000000351' and hidden_at is not null$$,
  $$values ('Spam'::text)$$,
  'moderators still read a hidden image, with its reason'
);

SELECT pg_temp.as_member(2);

SELECT results_eq(
  $$select count(*) from public.images
  where activity_id = 'f0000000-0000-4000-8000-000000000351' and hidden_at is not null$$,
  $$values (0::bigint)$$,
  'members don''t read a hidden image'
);

RESET ROLE;

SELECT results_eq(
  $$select status from public.reports
  where target_type = 'image'$$,
  $$values ('actioned'::text)$$,
  'hiding an image deals with its open reports'
);

SELECT * FROM finish();

ROLLBACK;
