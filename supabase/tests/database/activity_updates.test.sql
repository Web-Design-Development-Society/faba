-- Organizer updates to attendees (NOTIF-04). Run with `npm run db:test`.
BEGIN;

CREATE EXTENSION IF NOT EXISTS pgtap WITH SCHEMA extensions;

SELECT plan(18);

-- Otto organizes a hike, and a picnic a moderator hid. Gwen is going to the hike, Mia is a maybe,
-- Ned can't make it, and Sue is going but suspended. Ava hasn't answered. Otto moves to a new
-- account, Neo, at the end.
INSERT INTO auth.users
  (id, email, raw_user_meta_data)
SELECT
  ('c0000000-0000-4000-8000-00000000031' || n)::uuid,
  name || '@byui.edu',
  jsonb_build_object('full_name', name)
FROM (
  VALUES
    (1, 'otto'),
    (2, 'gwen'),
    (3, 'mia'),
    (4, 'ned'),
    (5, 'sue'),
    (6, 'ava'),
    (7, 'neo')
) AS v (n, name);

UPDATE public.profiles
SET
  guidelines_version = 1,
  guidelines_accepted_at = now(),
  status = CASE id WHEN 'c0000000-0000-4000-8000-000000000315' THEN 'suspended' ELSE 'active' END
WHERE id::text LIKE 'c0000000-0000-4000-8000-00000000031_';

INSERT INTO public.activities
  (
    id,
    organizer_id,
    category_id,
    title,
    starts_at,
    location_name,
    going_count,
    maybe_count,
    hidden_at
  )
VALUES
  (
    'f0000000-0000-4000-8000-000000000311',
    'c0000000-0000-4000-8000-000000000311',
    'outdoors',
    'Hike',
    now() + INTERVAL '1 day',
    'R Mountain trailhead',
    3,
    1,
    NULL
  ),
  (
    'f0000000-0000-4000-8000-000000000312',
    'c0000000-0000-4000-8000-000000000311',
    'food',
    'Picnic',
    now() + INTERVAL '2 days',
    'Porter Park',
    1,
    0,
    now()
  );

INSERT INTO public.rsvps
  (activity_id, user_id, status)
SELECT
  'f0000000-0000-4000-8000-000000000311',
  ('c0000000-0000-4000-8000-00000000031' || member)::uuid,
  status
FROM (
  VALUES
    ('1', 'going'),
    ('2', 'going'),
    ('3', 'maybe'),
    ('4', 'not_going'),
    ('5', 'going')
) AS v (member, status);

-- What each recipient has about the hike, read as the database owner.
CREATE FUNCTION pg_temp.sent()
RETURNS TABLE (who text, type text, update_id text, title text, actor text)
LANGUAGE sql
AS $$
  SELECT
    right(recipient_id::text, 1),
    type,
    payload->>'update_id',
    payload->>'title',
    right(actor_id::text, 1)
  FROM public.notifications
  WHERE activity_id = 'f0000000-0000-4000-8000-000000000311'
  ORDER BY recipient_id;
$$;

SET LOCAL ROLE anon;

SELECT throws_ok(
  'select from public.activity_updates',
  '42501',
  NULL,
  'signed-out visitors can''t read updates'
);

SET LOCAL ROLE authenticated;

SELECT set_config(
  'request.jwt.claims',
  '{"sub": "c0000000-0000-4000-8000-000000000312", "email": "gwen@byui.edu"}',
  TRUE
);

SELECT throws_ok(
  $$select public.post_activity_update('f0000000-0000-4000-8000-000000000311', 'Hi')$$,
  '42501',
  'NOT_ORGANIZER',
  'only the organizer posts updates'
);

SELECT throws_ok(
  $$insert into public.activity_updates (activity_id, author_id, body)
  values ('f0000000-0000-4000-8000-000000000311', 'c0000000-0000-4000-8000-000000000312', 'Hi')$$,
  '42501',
  NULL,
  'members can''t write updates directly'
);

-- Otto posts one, and the same tap arrives twice.
SELECT set_config(
  'request.jwt.claims',
  '{"sub": "c0000000-0000-4000-8000-000000000311", "email": "otto@byui.edu"}',
  TRUE
);

SELECT set_config(
  'test.first',
  public.post_activity_update(
    'f0000000-0000-4000-8000-000000000311',
    E'  Bring a headlamp!\n',
    'a0000000-0000-4000-8000-000000000311'
  )::text,
  TRUE
);

SELECT isnt(current_setting('test.first'), '', 'the organizer posts an update');

SELECT ok(
  public.post_activity_update(
    'f0000000-0000-4000-8000-000000000311',
    'Bring a headlamp!',
    'a0000000-0000-4000-8000-000000000311'
  )::text = current_setting('test.first'),
  'a repeated tap returns the same update'
);

RESET ROLE;

SELECT results_eq(
  $$select body from public.activity_updates where activity_id = 'f0000000-0000-4000-8000-000000000311'$$,
  $$values ('Bring a headlamp!'::text)$$,
  'it''s posted once, without the spaces around it'
);

SELECT results_eq(
  $$select who, type, update_id, title, actor from pg_temp.sent()$$,
  format(
    $$values
      ('2', 'organizer_update', %1$L, 'Hike', '1'),
      ('3', 'organizer_update', %1$L, 'Hike', '1')$$,
    current_setting('test.first')
  ),
  'those going or maybe hear about it once, but not the organizer, a can''t-make-it or a suspended member'
);

SET LOCAL ROLE authenticated;

SELECT throws_ok(
  $$select public.post_activity_update('f0000000-0000-4000-8000-000000000311', E' \n\t ')$$,
  '22023',
  'INVALID_BODY',
  'an update needs some text'
);

SELECT throws_ok(
  $$select public.post_activity_update('f0000000-0000-4000-8000-000000000311', repeat('a', 501))$$,
  '22023',
  'INVALID_BODY',
  'and no more than 500 characters'
);

SELECT lives_ok(
  $$select public.post_activity_update('f0000000-0000-4000-8000-000000000311', repeat('a', 500))$$,
  '500 is fine'
);

SELECT public.post_activity_update('f0000000-0000-4000-8000-000000000311', 'Update ' || n)
FROM generate_series(3, 5) AS n;

SELECT throws_ok(
  $$select public.post_activity_update('f0000000-0000-4000-8000-000000000311', 'One more')$$,
  'P0001',
  'UPDATE_QUOTA_EXCEEDED',
  'an activity gets at most 5 updates in 24 hours'
);

SELECT throws_ok(
  $$select public.post_activity_update('f0000000-0000-4000-8000-000000000312', 'Hi')$$,
  '22023',
  'ACTIVITY_HIDDEN',
  'a hidden activity takes no updates'
);

-- A moderator hides Otto's first update, and the picnic has one from before it was hidden.
RESET ROLE;

UPDATE public.activity_updates
SET hidden_at = now()
WHERE id = current_setting('test.first')::uuid;

INSERT INTO public.activity_updates
  (activity_id, author_id, body)
VALUES
  (
    'f0000000-0000-4000-8000-000000000312',
    'c0000000-0000-4000-8000-000000000311',
    'Bring a blanket'
  );

SET LOCAL ROLE authenticated;

SELECT set_config(
  'request.jwt.claims',
  '{"sub": "c0000000-0000-4000-8000-000000000316", "email": "ava@byui.edu"}',
  TRUE
);

SELECT results_eq(
  $$select count(*)::integer from public.activity_updates
  where activity_id = 'f0000000-0000-4000-8000-000000000311'$$,
  $$values (4)$$,
  'members read the updates to an activity they can see, going or not'
);

SELECT is_empty(
  format('select from public.activity_updates where id = %L', current_setting('test.first')),
  'but not a hidden update'
);

SELECT is_empty(
  $$select from public.activity_updates where activity_id = 'f0000000-0000-4000-8000-000000000312'$$,
  'or the updates to a hidden activity'
);

SELECT set_config(
  'request.jwt.claims',
  '{"sub": "c0000000-0000-4000-8000-000000000315", "email": "sue@byui.edu"}',
  TRUE
);

SELECT is_empty('select from public.activity_updates', 'a suspended member reads no updates');

RESET ROLE;

SELECT private.transfer_account(
  'c0000000-0000-4000-8000-000000000311',
  'c0000000-0000-4000-8000-000000000317',
  'Otto has a new account'
);

SELECT results_eq(
  $$select count(*)::integer from public.activity_updates
  where author_id = 'c0000000-0000-4000-8000-000000000317'$$,
  $$values (6)$$,
  'moving a member to a new account moves their updates too'
);

SELECT function_privs_are(
  'public',
  'post_activity_update',
  ARRAY['uuid', 'text', 'uuid'],
  'anon',
  ARRAY[]::text[],
  'signed-out visitors can''t post updates'
);

SELECT *
FROM finish();

ROLLBACK;
