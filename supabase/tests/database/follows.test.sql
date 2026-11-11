-- Following categories and groups (NOTIF-09). Run with `npm run db:test`.
BEGIN;

CREATE EXTENSION IF NOT EXISTS pgtap WITH SCHEMA extensions;

SELECT plan(8);

-- Oli organizes and owns a group. Fay follows the Outdoors category, Gus follows the group, and Ned
-- follows nothing.
INSERT INTO auth.users
  (id, email, raw_user_meta_data)
VALUES
  ('c0000000-0000-4000-8000-000000000701', 'oli@byui.edu', '{"full_name": "Oli Organizer"}'),
  ('c0000000-0000-4000-8000-000000000702', 'fay@byui.edu', '{"full_name": "Fay Fan"}'),
  ('c0000000-0000-4000-8000-000000000703', 'gus@byui.edu', '{"full_name": "Gus Group"}'),
  ('c0000000-0000-4000-8000-000000000704', 'ned@byui.edu', '{"full_name": "Ned Nobody"}');

UPDATE public.profiles
SET
  guidelines_version = 1,
  guidelines_accepted_at = now()
WHERE id BETWEEN 'c0000000-0000-4000-8000-000000000701' AND 'c0000000-0000-4000-8000-000000000704';

INSERT INTO public.groups
  (id, slug, name, category_id, join_policy, owner_id)
VALUES
  (
    'c0000000-0000-4000-8000-000000000710',
    'hikers-follow',
    'Hikers',
    'outdoors',
    'open',
    'c0000000-0000-4000-8000-000000000701'
  );

INSERT INTO public.group_members
  (group_id, user_id, role, status)
VALUES
  (
    'c0000000-0000-4000-8000-000000000710',
    'c0000000-0000-4000-8000-000000000701',
    'owner',
    'active'
  ),
  (
    'c0000000-0000-4000-8000-000000000710',
    'c0000000-0000-4000-8000-000000000703',
    'member',
    'active'
  );

-- Fay follows the category, through the function.
SET LOCAL ROLE authenticated;

SELECT set_config(
  'request.jwt.claims',
  '{"sub": "c0000000-0000-4000-8000-000000000702", "email": "fay@byui.edu"}',
  TRUE
);

SELECT results_eq(
  $$select public.set_follow('category', 'outdoors', true)$$,
  $$values (true)$$,
  'a member can follow a category'
);

-- Gus follows the group.
SELECT set_config(
  'request.jwt.claims',
  '{"sub": "c0000000-0000-4000-8000-000000000703", "email": "gus@byui.edu"}',
  TRUE
);

SELECT lives_ok(
  $$select public.set_follow('group', 'c0000000-0000-4000-8000-000000000710', true)$$,
  'a member can follow a group'
);

RESET ROLE;

-- Oli posts an Outdoors activity. Fay hears about it once.
INSERT INTO public.activities
  (id, organizer_id, category_id, title, starts_at, location_name)
VALUES
  (
    'c0000000-0000-4000-8000-000000000720',
    'c0000000-0000-4000-8000-000000000701',
    'outdoors',
    'Morning hike',
    now() + INTERVAL '2 days',
    'Trailhead'
  );

-- A second activity the same day makes the same notification, with a count of 2.
INSERT INTO public.activities
  (id, organizer_id, category_id, title, starts_at, location_name)
VALUES
  (
    'c0000000-0000-4000-8000-000000000721',
    'c0000000-0000-4000-8000-000000000701',
    'outdoors',
    'Evening walk',
    now() + INTERVAL '3 days',
    'Park'
  );

SELECT results_eq(
  $$select count(*)::int from public.notifications where recipient_id = 'c0000000-0000-4000-8000-000000000702' and type = 'new_activity'$$,
  $$values (1)$$,
  'a follower gets one batched notification a day, not one per activity'
);

SELECT results_eq(
  $$select payload->>'count' from public.notifications where recipient_id = 'c0000000-0000-4000-8000-000000000702' and type = 'new_activity'$$,
  $$values ('2')$$,
  'the batched notification counts the day''s activities'
);

-- Ned follows nothing, so hears nothing.
SELECT results_eq(
  $$select count(*)::int from public.notifications where recipient_id = 'c0000000-0000-4000-8000-000000000704'$$,
  $$values (0)$$,
  'someone who follows nothing gets nothing'
);

-- A group activity reaches the group's follower, but not the category follower.
INSERT INTO public.activities
  (id, organizer_id, category_id, title, starts_at, location_name, visibility, group_id)
VALUES
  (
    'c0000000-0000-4000-8000-000000000722',
    'c0000000-0000-4000-8000-000000000701',
    'outdoors',
    'Group hike',
    now() + INTERVAL '4 days',
    'Canyon',
    'group',
    'c0000000-0000-4000-8000-000000000710'
  );

SELECT results_eq(
  $$select count(*)::int from public.notifications where recipient_id = 'c0000000-0000-4000-8000-000000000703' and type = 'new_activity'$$,
  $$values (1)$$,
  'a group follower hears about the group''s activities'
);

-- Fay unfollows, and a later activity doesn't reach her.
SET LOCAL ROLE authenticated;

SELECT set_config(
  'request.jwt.claims',
  '{"sub": "c0000000-0000-4000-8000-000000000702", "email": "fay@byui.edu"}',
  TRUE
);

SELECT results_eq(
  $$select public.set_follow('category', 'outdoors', false)$$,
  $$values (false)$$,
  'a member can unfollow'
);

RESET ROLE;

INSERT INTO public.activities
  (id, organizer_id, category_id, title, starts_at, location_name)
VALUES
  (
    'c0000000-0000-4000-8000-000000000723',
    'c0000000-0000-4000-8000-000000000701',
    'outdoors',
    'Sunset stroll',
    now() + INTERVAL '5 days',
    'Lake'
  );

SELECT results_eq(
  $$select payload->>'count' from public.notifications where recipient_id = 'c0000000-0000-4000-8000-000000000702' and type = 'new_activity'$$,
  $$values ('2')$$,
  'an unfollowed member gets no more batches'
);

SELECT * FROM finish();
ROLLBACK;
