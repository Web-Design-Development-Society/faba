-- Private details for attendees (ACT-09), and the notification when they change (NOTIF-02). Run
-- with `npm run db:test`.
BEGIN;

CREATE EXTENSION IF NOT EXISTS pgtap WITH SCHEMA extensions;

SELECT plan(24);

-- Otto organizes a hike with a gate code, a picnic a moderator hid, two past activities and one
-- that has started. Gwen is going to the hike, Mia is a maybe, Ned can't make it, and Max is going
-- but muted it. Ava hasn't answered. Mo is a moderator. Dee organizes a game night and deletes her
-- account at the end.
INSERT INTO auth.users
  (id, email, raw_user_meta_data)
SELECT
  ('c0000000-0000-4000-8000-00000000034' || n)::uuid,
  name || '@byui.edu',
  jsonb_build_object('full_name', name)
FROM (
  VALUES
    (1, 'otto'),
    (2, 'gwen'),
    (3, 'mia'),
    (4, 'ned'),
    (5, 'mo'),
    (6, 'ava'),
    (7, 'max'),
    (8, 'dee')
) AS v (n, name);

UPDATE public.profiles
SET
  guidelines_version = 1,
  guidelines_accepted_at = now(),
  status = 'active',
  role = CASE id WHEN 'c0000000-0000-4000-8000-000000000345' THEN 'moderator' ELSE 'member' END
WHERE id::text LIKE 'c0000000-0000-4000-8000-00000000034_';

INSERT INTO public.activities
  (
    id,
    organizer_id,
    category_id,
    title,
    starts_at,
    ends_at,
    location_name,
    hidden_at,
    has_private_details
  )
VALUES
  (
    'f0000000-0000-4000-8000-000000000341',
    'c0000000-0000-4000-8000-000000000341',
    'outdoors',
    'Hike',
    now() + INTERVAL '1 day',
    NULL,
    'R Mountain trailhead',
    NULL,
    TRUE
  ),
  (
    'f0000000-0000-4000-8000-000000000342',
    'c0000000-0000-4000-8000-000000000341',
    'food',
    'Picnic',
    now() + INTERVAL '2 days',
    NULL,
    'Porter Park',
    now(),
    TRUE
  ),
  (
    'f0000000-0000-4000-8000-000000000343',
    'c0000000-0000-4000-8000-000000000341',
    'food',
    'Old dinner',
    now() - INTERVAL '31 days 2 hours',
    now() - INTERVAL '31 days',
    'Otto''s house',
    NULL,
    TRUE
  ),
  (
    'f0000000-0000-4000-8000-000000000344',
    'c0000000-0000-4000-8000-000000000341',
    'food',
    'Recent dinner',
    now() - INTERVAL '29 days 2 hours',
    now() - INTERVAL '29 days',
    'Otto''s house',
    NULL,
    TRUE
  ),
  (
    'f0000000-0000-4000-8000-000000000345',
    'c0000000-0000-4000-8000-000000000348',
    'games',
    'Game night',
    now() + INTERVAL '3 days',
    NULL,
    'Dee''s house',
    NULL,
    TRUE
  ),
  (
    'f0000000-0000-4000-8000-000000000346',
    'c0000000-0000-4000-8000-000000000341',
    'outdoors',
    'Sunrise walk',
    now() - INTERVAL '1 hour',
    NULL,
    'Porter Park',
    NULL,
    FALSE
  );

INSERT INTO public.activity_private_details
  (activity_id, details)
VALUES
  ('f0000000-0000-4000-8000-000000000341', 'Gate code 1234'),
  ('f0000000-0000-4000-8000-000000000342', 'The blue house'),
  ('f0000000-0000-4000-8000-000000000343', '12 Elm Street'),
  ('f0000000-0000-4000-8000-000000000344', '12 Elm Street'),
  ('f0000000-0000-4000-8000-000000000345', '34 Oak Street');

INSERT INTO public.rsvps
  (activity_id, user_id, status)
SELECT
  ('f0000000-0000-4000-8000-00000000034' || activity)::uuid,
  ('c0000000-0000-4000-8000-00000000034' || member)::uuid,
  status
FROM (
  VALUES
    ('1', '1', 'going'),
    ('1', '2', 'going'),
    ('1', '3', 'maybe'),
    ('1', '4', 'not_going'),
    ('1', '7', 'going'),
    ('2', '1', 'going'),
    ('2', '2', 'going'),
    ('5', '8', 'going')
) AS v (activity, member, status);

-- The counts those RSVPs make.
UPDATE public.activities AS a
SET
  going_count = (
    SELECT count(*) FROM public.rsvps AS r WHERE r.activity_id = a.id AND r.status = 'going'
  ),
  maybe_count = (
    SELECT count(*) FROM public.rsvps AS r WHERE r.activity_id = a.id AND r.status = 'maybe'
  )
WHERE a.id::text LIKE 'f0000000-0000-4000-8000-00000000034_';

INSERT INTO public.activity_mutes
  (activity_id, user_id)
VALUES
  ('f0000000-0000-4000-8000-000000000341', 'c0000000-0000-4000-8000-000000000347');

-- Signs in as member n.
CREATE FUNCTION pg_temp.sign_in(n text)
RETURNS void
LANGUAGE sql
AS $$
  SELECT set_config(
    'request.jwt.claims',
    jsonb_build_object(
      'sub',
      'c0000000-0000-4000-8000-00000000034' || n,
      'email',
      'm@byui.edu'
    )::text,
    TRUE
  );
$$;

-- The hike's private details, as the signed-in member can read them.
CREATE FUNCTION pg_temp.hike_details()
RETURNS SETOF text
LANGUAGE sql
AS $$
  SELECT details
  FROM public.activity_private_details
  WHERE activity_id = 'f0000000-0000-4000-8000-000000000341';
$$;

-- Edits the hike as the signed-in member, at its current version.
CREATE FUNCTION pg_temp.edit_hike(patch jsonb)
RETURNS void
LANGUAGE sql
AS $$
  SELECT public.update_activity(
    'f0000000-0000-4000-8000-000000000341',
    patch,
    (SELECT version FROM public.activities WHERE id = 'f0000000-0000-4000-8000-000000000341')
  );
$$;

GRANT EXECUTE ON ALL FUNCTIONS IN SCHEMA pg_temp TO authenticated;

-- What each recipient has about the hike, read as the database owner.
CREATE FUNCTION pg_temp.sent()
RETURNS TABLE (who text, details_changed text, place text, unread BOOLEAN)
LANGUAGE sql
AS $$
  SELECT
    right(recipient_id::text, 1),
    payload->>'details_changed',
    payload->'after'->>'location_name',
    read_at IS NULL
  FROM public.notifications
  WHERE activity_id = 'f0000000-0000-4000-8000-000000000341' AND type = 'activity_changed'
  ORDER BY recipient_id;
$$;

SET LOCAL ROLE anon;

SELECT throws_ok(
  'select from public.activity_private_details',
  '42501',
  NULL,
  'signed-out visitors can''t read private details'
);

-- Who reads them.
SET LOCAL ROLE authenticated;

SELECT pg_temp.sign_in('1');

SELECT results_eq(
  'select pg_temp.hike_details()',
  $$values ('Gate code 1234')$$,
  'the organizer reads them'
);

SELECT pg_temp.sign_in('2');

SELECT results_eq(
  'select pg_temp.hike_details()',
  $$values ('Gate code 1234')$$,
  'a member going reads them'
);

SELECT pg_temp.sign_in('3');

SELECT is_empty('select pg_temp.hike_details()', 'a maybe doesn''t');

SELECT pg_temp.sign_in('4');

SELECT is_empty('select pg_temp.hike_details()', 'nor does a member who can''t make it');

SELECT pg_temp.sign_in('6');

SELECT is_empty('select pg_temp.hike_details()', 'nor does one who hasn''t answered');

SELECT ok(
  (
    SELECT has_private_details
    FROM public.activities
    WHERE id = 'f0000000-0000-4000-8000-000000000341'
  ),
  'but they can see the hike has some'
);

SELECT pg_temp.sign_in('5');

SELECT results_eq(
  'select pg_temp.hike_details()',
  $$values ('Gate code 1234')$$,
  'a moderator reads them'
);

SELECT pg_temp.sign_in('2');

SELECT is_empty(
  $$select from public.activity_private_details
  where activity_id = 'f0000000-0000-4000-8000-000000000342'$$,
  'nobody going reads a hidden activity''s details'
);

SELECT pg_temp.sign_in('1');

SELECT results_eq(
  $$select details from public.activity_private_details
  where activity_id = 'f0000000-0000-4000-8000-000000000342'$$,
  $$values ('The blue house')$$,
  'but its organizer does'
);

SELECT throws_ok(
  $$insert into public.activity_private_details (activity_id, details)
  values ('f0000000-0000-4000-8000-000000000346', 'Hi')$$,
  '42501',
  NULL,
  'nobody writes them directly'
);

-- Posting an activity with them.
SELECT set_config(
  'test.posted',
  public.create_activity(
    title => 'Board games',
    category_id => 'games',
    starts_at => now() + INTERVAL '4 days',
    location_name => 'Otto''s house',
    private_details => E'  Apartment 5, buzz twice\n'
  )::text,
  TRUE
);

RESET ROLE;

SELECT results_eq(
  format(
    $$select d.details, a.has_private_details
    from public.activities as a
    join public.activity_private_details as d on d.activity_id = a.id
    where a.id = %L$$,
    current_setting('test.posted')
  ),
  $$values ('Apartment 5, buzz twice', true)$$,
  'posting an activity saves its details, without the spaces around them'
);

SET LOCAL ROLE authenticated;

SELECT throws_ok(
  $$select public.create_activity(
    title => 'Board games',
    category_id => 'games',
    starts_at => now() + INTERVAL '4 days',
    location_name => 'Otto''s house',
    private_details => repeat('a', 501)
  )$$,
  '22023',
  'INVALID_PRIVATE_DETAILS',
  'details are 500 characters at most'
);

-- Editing them.
SELECT pg_temp.edit_hike('{"description": "Bring water"}');

RESET ROLE;

SELECT ok(
  (
    SELECT details
    FROM public.activity_private_details
    WHERE activity_id = 'f0000000-0000-4000-8000-000000000341'
  ) = 'Gate code 1234'
  AND NOT EXISTS (
    SELECT FROM public.notifications WHERE activity_id = 'f0000000-0000-4000-8000-000000000341'
  ),
  'an edit without them keeps them, and tells nobody'
);

SET LOCAL ROLE authenticated;

SELECT pg_temp.edit_hike('{"private_details": "Gate code 5678"}');

RESET ROLE;

SELECT results_eq(
  'select who, details_changed, place, unread from pg_temp.sent()',
  $$values
    ('2', 'true', 'R Mountain trailhead', true),
    ('3', 'true', 'R Mountain trailhead', true)$$,
  'a change tells those going or maybe, but not the organizer, a can''t-make-it, a muted member or someone who hasn''t answered'
);

SELECT ok(
  NOT EXISTS (
    SELECT
    FROM public.notifications
    WHERE payload::text LIKE '%5678%' OR payload::text LIKE '%1234%'
  ),
  'the notification doesn''t hold the details'
);

UPDATE public.notifications
SET read_at = now()
WHERE activity_id = 'f0000000-0000-4000-8000-000000000341';

SET LOCAL ROLE authenticated;

SELECT pg_temp.edit_hike('{"private_details": " Gate code 5678 "}');

RESET ROLE;

SELECT ok(
  NOT EXISTS (
    SELECT
    FROM public.notifications
    WHERE activity_id = 'f0000000-0000-4000-8000-000000000341' AND read_at IS NULL
  ),
  'saving the same details again tells nobody'
);

SET LOCAL ROLE authenticated;

SELECT pg_temp.edit_hike('{"location_name": "Kelly Canyon"}');

RESET ROLE;

SELECT results_eq(
  'select who, details_changed, place, unread from pg_temp.sent()',
  $$values
    ('2', 'true', 'Kelly Canyon', true),
    ('3', 'true', 'Kelly Canyon', true)$$,
  'a new place within 10 minutes makes it unread again, and still says the details changed'
);

SET LOCAL ROLE authenticated;

SELECT pg_temp.edit_hike('{"private_details": "  "}');

RESET ROLE;

SELECT ok(
  NOT EXISTS (
    SELECT
    FROM public.activity_private_details
    WHERE activity_id = 'f0000000-0000-4000-8000-000000000341'
  )
  AND NOT (
    SELECT has_private_details
    FROM public.activities
    WHERE id = 'f0000000-0000-4000-8000-000000000341'
  ),
  'empty details delete them'
);

SET LOCAL ROLE authenticated;

SELECT lives_ok(
  $$select public.update_activity(
    'f0000000-0000-4000-8000-000000000346',
    '{"private_details": "Meet at the north gate"}',
    (select version from public.activities where id = 'f0000000-0000-4000-8000-000000000346')
  )$$,
  'they can change once an activity has started, as the description can'
);

SELECT pg_temp.sign_in('2');

SELECT throws_ok(
  $$select pg_temp.edit_hike('{"private_details": "Mine now"}')$$,
  '42501',
  'NOT_ORGANIZER',
  'only the organizer changes them'
);

-- Deleting them.
RESET ROLE;

SELECT private.purge_old_data();

SELECT results_eq(
  $$select a.title, d.details, a.has_private_details
  from public.activities as a
  left join public.activity_private_details as d on d.activity_id = a.id
  where a.id in ('f0000000-0000-4000-8000-000000000343', 'f0000000-0000-4000-8000-000000000344')
  order by a.title$$,
  $$values ('Old dinner', null, false), ('Recent dinner', '12 Elm Street', true)$$,
  'they''re deleted 30 days after the activity ends'
);

SET LOCAL ROLE authenticated;

SELECT pg_temp.sign_in('8');

SELECT lives_ok('select public.delete_my_account()', 'Dee deletes her account');

RESET ROLE;

SELECT ok(
  NOT EXISTS (
    SELECT
    FROM public.activity_private_details
    WHERE activity_id = 'f0000000-0000-4000-8000-000000000345'
  )
  AND NOT (
    SELECT has_private_details
    FROM public.activities
    WHERE id = 'f0000000-0000-4000-8000-000000000345'
  ),
  'and the details of the activities she organized go with it'
);

SELECT * FROM finish();

ROLLBACK;
