-- Local test data: five personas and 50 activities over the next 6 weeks.
-- Loaded by `supabase start` on a new database, and by `supabase db reset`.
-- Local only: never run it against staging or production.
--
-- Every persona signs in with the password faba-local-dev. Email sign-up is off, so these
-- seeded accounts are the only password users (design document section 11.2).
INSERT INTO auth.users
  (
    instance_id,
    id,
    aud,
    role,
    email,
    encrypted_password,
    email_confirmed_at,
    raw_app_meta_data,
    raw_user_meta_data,
    created_at,
    updated_at,
    confirmation_token,
    recovery_token,
    email_change_token_new,
    email_change,
    email_change_token_current,
    reauthentication_token,
    phone_change,
    phone_change_token
  )
SELECT
  '00000000-0000-0000-0000-000000000000',
  p.id,
  'authenticated',
  'authenticated',
  p.email,
  extensions.crypt('faba-local-dev', extensions.gen_salt('bf')),
  now(),
  '{"provider": "email", "providers": ["email"]}',
  jsonb_build_object('full_name', p.full_name),
  now(),
  now(),
  '',
  '',
  '',
  '',
  '',
  '',
  '',
  ''
FROM (
  VALUES
    ('00000000-0000-4000-8000-000000000001'::uuid, 'member.test@byui.edu', 'Maya Member'),
    ('00000000-0000-4000-8000-000000000002'::uuid, 'organizer.test@byui.edu', 'Oscar Organizer'),
    ('00000000-0000-4000-8000-000000000003'::uuid, 'moderator.test@byui.edu', 'Morgan Moderator'),
    ('00000000-0000-4000-8000-000000000004'::uuid, 'admin.test@byui.edu', 'Ada Admin'),
    ('00000000-0000-4000-8000-000000000005'::uuid, 'suspended.test@byui.edu', 'Sam Suspended')
) AS p (id, email, full_name);

INSERT INTO auth.identities
  (provider_id, user_id, identity_data, provider, last_sign_in_at, created_at, updated_at)
SELECT
  id::text,
  id,
  jsonb_build_object('sub', id::text, 'email', email, 'email_verified', TRUE),
  'email',
  now(),
  now(),
  now()
FROM auth.users
WHERE email LIKE '%.test@byui.edu';

-- The on_auth_user_created trigger made the profiles. Fill them in, and accept the guidelines
-- so the personas skip the Welcome screen.
UPDATE public.profiles AS p
SET
  role = v.role,
  status = v.status,
  department = v.department,
  bio = v.bio,
  interests = v.interests,
  guidelines_version = 1,
  guidelines_accepted_at = now()
FROM (
  VALUES
    (
      '00000000-0000-4000-8000-000000000001'::uuid,
      'member',
      'active',
      'English',
      'Part-time instructor. Always up for a board game.',
      ARRAY['games', 'food']
    ),
    (
      '00000000-0000-4000-8000-000000000002'::uuid,
      'member',
      'active',
      'Biology',
      'I organize hikes and anything outdoors.',
      ARRAY['outdoors', 'sports', 'service']
    ),
    (
      '00000000-0000-4000-8000-000000000003'::uuid,
      'moderator',
      'active',
      'Mathematics',
      'FABA board member and moderator.',
      ARRAY['learning', 'arts']
    ),
    (
      '00000000-0000-4000-8000-000000000004'::uuid,
      'admin',
      'active',
      'Computer Science',
      'FABA board member and admin.',
      ARRAY['games', 'family']
    ),
    (
      '00000000-0000-4000-8000-000000000005'::uuid,
      'member',
      'suspended',
      NULL,
      NULL,
      ARRAY[]::text[]
    )
) AS v (id, role, status, department, bio, interests)
WHERE p.id = v.id;

UPDATE public.profiles
SET public_email = 'organizer.test@byui.edu'
WHERE id = '00000000-0000-4000-8000-000000000002';

UPDATE public.profile_private
SET
  email_visible = (user_id = '00000000-0000-4000-8000-000000000002'),
  faculty_type = CASE
    WHEN user_id = '00000000-0000-4000-8000-000000000001' THEN 'part_time'
    ELSE 'full_time'
  END;

-- 49 activities from 20 templates, spread over the next 6 weeks in Rexburg time, skipping
-- Sundays. Two are cancelled. Counts stay at 0 until RSVPs exist (ADR-008).
WITH
  templates(n, title, category_id, location_name, local_start, minutes, cost_note, description) AS (
    VALUES
      (
        0,
        'Morning hike at Kelly Canyon',
        'outdoors',
        'Kelly Canyon trailhead',
        TIME '09:00',
        180,
        NULL,
        'An easy to moderate hike. Dress in layers and bring water.'
      ),
      (
        1,
        'Sunset walk at the sand dunes',
        'outdoors',
        'St. Anthony Sand Dunes',
        TIME '16:00',
        120,
        NULL,
        'A relaxed walk on the dunes. We carpool from Porter Park.'
      ),
      (
        2,
        'Snowshoeing near Mesa Falls',
        'outdoors',
        'Upper Mesa Falls parking area',
        TIME '10:00',
        240,
        'Bring or rent snowshoes',
        'Beginners welcome. We go at the slowest person''s pace.'
      ),
      (
        3,
        'Lunchtime pickup basketball',
        'sports',
        'Hart Building, court 3',
        TIME '12:00',
        60,
        NULL,
        'Casual games for all skill levels.'
      ),
      (
        4,
        'Pickleball for beginners',
        'sports',
        'Hart Building, court 2',
        TIME '17:30',
        90,
        NULL,
        'Paddles provided. Learn the rules and play a few games.'
      ),
      (
        5,
        'Early morning run',
        'sports',
        'Smith Park',
        TIME '06:30',
        45,
        NULL,
        'About 3 miles at a conversational pace.'
      ),
      (
        6,
        'Board game night',
        'games',
        'Madison Library meeting room',
        TIME '19:00',
        150,
        NULL,
        'Bring a favorite game or learn a new one.'
      ),
      (
        7,
        'Chess at lunch',
        'games',
        'Manwaring Center',
        TIME '12:00',
        60,
        NULL,
        'Boards provided. Drop in for one game or stay the hour.'
      ),
      (
        8,
        'Strategy game afternoon',
        'games',
        'Madison Library meeting room',
        TIME '14:00',
        180,
        NULL,
        'Longer games for people who like to plan ahead.'
      ),
      (
        9,
        'Faculty potluck',
        'food',
        'Porter Park pavilion',
        TIME '18:00',
        120,
        NULL,
        'Bring a dish to share. Plates and drinks provided.'
      ),
      (
        10,
        'Lunch out downtown',
        'food',
        'Main Street, downtown Rexburg',
        TIME '12:00',
        60,
        'Pay your own way',
        'A different local restaurant each time.'
      ),
      (
        11,
        'Soup and bread night',
        'food',
        'Madison Library community room',
        TIME '18:30',
        90,
        '$3 for supplies',
        'A simple dinner and good conversation.'
      ),
      (
        12,
        'Watercolor for beginners',
        'arts',
        'Madison Library meeting room',
        TIME '19:00',
        90,
        '$5 for supplies',
        'No experience needed. All supplies provided.'
      ),
      (
        13,
        'Quilting circle',
        'arts',
        'Madison Library community room',
        TIME '10:00',
        120,
        NULL,
        'Bring a project in progress, or come learn the basics.'
      ),
      (
        14,
        'Photography walk',
        'arts',
        'Porter Park',
        TIME '16:30',
        90,
        NULL,
        'Any camera works, including your phone.'
      ),
      (
        15,
        'Faculty book club',
        'learning',
        'Madison Library meeting room',
        TIME '19:00',
        75,
        NULL,
        'This month: a short novel chosen by the group.'
      ),
      (
        16,
        'Intro to bread baking',
        'learning',
        'Madison Library community room',
        TIME '18:00',
        120,
        '$5 for ingredients',
        'Learn a simple no-knead loaf to bake at home.'
      ),
      (
        17,
        'Food pantry sorting',
        'service',
        'Community food pantry, Rexburg',
        TIME '09:00',
        120,
        NULL,
        'Help sort donations. Closed-toe shoes required.'
      ),
      (
        18,
        'Family movie night',
        'family',
        'Madison Library community room',
        TIME '18:30',
        120,
        'Free, kids welcome',
        'A family-friendly movie with popcorn.'
      ),
      (
        19,
        'Sledding afternoon',
        'family',
        'Porter Park',
        TIME '14:00',
        120,
        NULL,
        'Bring sleds and warm clothes. Hot chocolate after.'
      )
  ),
  slots AS (
    SELECT
      i,
      (now() AT TIME ZONE 'America/Denver')::date + 1 + (i * 41) % 42 AS day
    FROM generate_series(0, 48) AS i
  ),
  dated AS (
    SELECT
      i,
      CASE
        WHEN EXTRACT(DOW FROM day) = 0 THEN day + 1
        ELSE day
      END AS day
    FROM slots
  )
INSERT INTO public.activities
  (
    organizer_id,
    category_id,
    title,
    description,
    starts_at,
    ends_at,
    location_name,
    cost_note,
    status,
    cancel_reason,
    cancelled_at
  )
SELECT
  CASE i % 5
    WHEN 2 THEN '00000000-0000-4000-8000-000000000001'::uuid
    WHEN 3 THEN '00000000-0000-4000-8000-000000000003'::uuid
    WHEN 4 THEN '00000000-0000-4000-8000-000000000004'::uuid
    ELSE '00000000-0000-4000-8000-000000000002'::uuid
  END,
  t.category_id,
  t.title,
  t.description,
  (d.day + t.local_start) AT TIME ZONE 'America/Denver',
  (d.day + t.local_start) AT TIME ZONE 'America/Denver' + make_interval(mins => t.minutes),
  t.location_name,
  t.cost_note,
  CASE
    WHEN i IN (7, 23) THEN 'cancelled'
    ELSE 'published'
  END,
  CASE i
    WHEN 7 THEN 'Not enough people could make it this week.'
    WHEN 23 THEN 'Bad weather. We will reschedule.'
  END,
  CASE
    WHEN i IN (7, 23) THEN now()
  END
FROM dated AS d
JOIN templates AS t ON t.n = d.i % 20;

-- One hidden activity: a commercial post by the suspended persona, hidden by the moderator.
-- It's on the first Saturday at least a week away.
WITH
  saturday AS (
    SELECT (now() AT TIME ZONE 'America/Denver')::date + 7 +
      (6 - EXTRACT(DOW FROM (now() AT TIME ZONE 'America/Denver')::date + 7))::INTEGER AS day
  )
INSERT INTO public.activities
  (
    organizer_id,
    category_id,
    title,
    description,
    starts_at,
    ends_at,
    location_name,
    hidden_at,
    hidden_reason,
    hidden_by
  )
SELECT
  '00000000-0000-4000-8000-000000000005',
  'other',
  'Business opportunity info night',
  'Learn how to earn extra income from home. Products for sale.',
  (day + TIME '19:00') AT TIME ZONE 'America/Denver',
  (day + TIME '20:00') AT TIME ZONE 'America/Denver',
  'Madison Library meeting room',
  now(),
  'Commercial post. Against the community guidelines.',
  '00000000-0000-4000-8000-000000000003'
FROM saturday;
