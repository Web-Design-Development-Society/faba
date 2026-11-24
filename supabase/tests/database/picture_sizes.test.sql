-- A picture's space before it loads (MEDIA-04): a picture keeps its width and height. Run with
-- `npm run db:test`.
BEGIN;

CREATE EXTENSION IF NOT EXISTS pgtap WITH SCHEMA extensions;

SELECT plan(15);

-- Pia organizes a swim and runs a group.
INSERT INTO auth.users
  (id, email, raw_user_meta_data)
VALUES
  ('c0000000-0000-4000-8000-000000000541', 'pia@byui.edu', jsonb_build_object('full_name', 'pia'));

UPDATE public.profiles
SET
  guidelines_version = 1,
  guidelines_accepted_at = now()
WHERE id = 'c0000000-0000-4000-8000-000000000541';

INSERT INTO public.groups
  (id, slug, name, category_id, join_policy, owner_id)
VALUES
  (
    'b0000000-0000-4000-8000-000000000541',
    'swimmers-541',
    'Swimmers',
    'sports',
    'open',
    'c0000000-0000-4000-8000-000000000541'
  );

INSERT INTO public.group_members
  (group_id, user_id, role)
VALUES
  ('b0000000-0000-4000-8000-000000000541', 'c0000000-0000-4000-8000-000000000541', 'owner');

INSERT INTO public.activities
  (id, organizer_id, category_id, title, starts_at, location_name)
VALUES
  (
    'f0000000-0000-4000-8000-000000000541',
    'c0000000-0000-4000-8000-000000000541',
    'sports',
    'Swim',
    now() + INTERVAL '1 day',
    'Hart pool'
  );

SET LOCAL ROLE authenticated;

SELECT set_config(
  'request.jwt.claims',
  '{"sub": "c0000000-0000-4000-8000-000000000541", "email": "pia@byui.edu"}',
  TRUE
);

-- A tall phone photo as the cover.
SELECT lives_ok(
  $$select public.set_activity_cover(
    activity_id => 'f0000000-0000-4000-8000-000000000541',
    r2_key => 'activities/tall',
    content_type => 'image/jpeg',
    bytes => 300000,
    alt => 'A swimmer on the block',
    width => 1200,
    height => 1600
  )$$,
  'an organizer sets a cover with its size'
);

SELECT results_eq(
  $$select i.width, i.height from public.images as i where i.r2_key = 'activities/tall'$$,
  $$values (1200, 1600)$$,
  'a cover keeps its width and height'
);

SELECT results_eq(
  $$select i.width, i.height from public.activities as a
  join public.images as i on i.id = a.cover_image_id
  where a.id = 'f0000000-0000-4000-8000-000000000541'$$,
  $$values (1200, 1600)$$,
  'and the activity shows it'
);

-- The Worker from before this, while it's deployed, sends no size.
SELECT lives_ok(
  $$select public.set_activity_cover(
    'f0000000-0000-4000-8000-000000000541',
    'activities/no-size',
    'image/jpeg',
    300000,
    'The pool'
  )$$,
  'a cover can be set with no size, as before'
);

SELECT results_eq(
  $$select i.width is null and i.height is null from public.images as i
  where i.r2_key = 'activities/no-size'$$,
  $$values (true)$$,
  'and it has none'
);

SELECT lives_ok(
  $$select public.set_group_banner(
    group_id => 'b0000000-0000-4000-8000-000000000541',
    r2_key => 'groups/wide',
    content_type => 'image/png',
    bytes => 200000,
    alt => 'Lanes from above',
    width => 1600,
    height => 900
  )$$,
  'a group''s owner sets a banner with its size'
);

SELECT results_eq(
  $$select i.width, i.height from public.groups as g
  join public.images as i on i.id = g.banner_image_id
  where g.id = 'b0000000-0000-4000-8000-000000000541'$$,
  $$values (1600, 900)$$,
  'a banner keeps its width and height'
);

SELECT lives_ok(
  $$select public.set_profile_photo(
    r2_key => 'profiles/face',
    content_type => 'image/webp',
    bytes => 50000,
    width => 640,
    height => 640
  )$$,
  'a member sets their photo with its size'
);

SELECT results_eq(
  $$select i.width, i.height from public.profiles as p
  join public.images as i on i.id = p.photo_image_id
  where p.id = 'c0000000-0000-4000-8000-000000000541'$$,
  $$values (640, 640)$$,
  'and the photo keeps it'
);

-- A size that can't be a picture's.
SELECT throws_ok(
  $$select public.set_activity_cover(
    activity_id => 'f0000000-0000-4000-8000-000000000541',
    r2_key => 'activities/half',
    content_type => 'image/jpeg',
    bytes => 300000,
    alt => 'Half a size',
    width => 1200
  )$$,
  '23514',
  NULL,
  'a width without a height is refused'
);

SELECT throws_ok(
  $$select public.set_activity_cover(
    activity_id => 'f0000000-0000-4000-8000-000000000541',
    r2_key => 'activities/flat',
    content_type => 'image/jpeg',
    bytes => 300000,
    alt => 'No height',
    width => 1200,
    height => 0
  )$$,
  '23514',
  NULL,
  'a side of nothing is refused'
);

SELECT throws_ok(
  $$select public.set_group_banner(
    group_id => 'b0000000-0000-4000-8000-000000000541',
    r2_key => 'groups/huge',
    content_type => 'image/png',
    bytes => 200000,
    alt => 'Too wide',
    width => 65536,
    height => 900
  )$$,
  '23514',
  NULL,
  'a side longer than a JPEG''s can be is refused'
);

RESET ROLE;

-- Each function has one version, which takes the size, and only members can call it.
SELECT ok(
  to_regprocedure('public.set_activity_cover(uuid, text, text, integer, text)') IS NULL
  AND to_regprocedure('public.set_group_banner(uuid, text, text, integer, text)') IS NULL
  AND to_regprocedure('public.set_profile_photo(text, text, integer)') IS NULL,
  'the functions that add a picture without its size are gone'
);

SELECT ok(
  NOT has_function_privilege(
    'anon',
    'public.set_activity_cover(uuid, text, text, integer, text, integer, integer)',
    'execute'
  )
  AND NOT has_function_privilege(
    'anon',
    'public.set_group_banner(uuid, text, text, integer, text, integer, integer)',
    'execute'
  )
  AND NOT has_function_privilege(
    'anon',
    'public.set_profile_photo(text, text, integer, integer, integer)',
    'execute'
  ),
  'someone signed out can''t add a picture'
);

SELECT ok(
  has_function_privilege(
    'authenticated',
    'public.set_activity_cover(uuid, text, text, integer, text, integer, integer)',
    'execute'
  )
  AND has_function_privilege(
    'authenticated',
    'public.set_group_banner(uuid, text, text, integer, text, integer, integer)',
    'execute'
  )
  AND has_function_privilege(
    'authenticated',
    'public.set_profile_photo(text, text, integer, integer, integer)',
    'execute'
  ),
  'a member can'
);

SELECT *
FROM finish();

ROLLBACK;
