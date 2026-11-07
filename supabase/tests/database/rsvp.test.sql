-- Saying "I'm in" (RSVP-01). Run with `npm run db:test`.
BEGIN;

CREATE EXTENSION IF NOT EXISTS pgtap WITH SCHEMA extensions;

SELECT plan(17);

-- Rita RSVPs, Olga organizes, and Nell hasn't accepted the guidelines.
INSERT INTO auth.users
  (id, email, raw_user_meta_data)
VALUES
  ('c0000000-0000-4000-8000-000000000021', 'rita.rsvp@byui.edu', '{"full_name": "Rita Rsvp"}'),
  ('c0000000-0000-4000-8000-000000000022', 'olga.org@byui.edu', '{"full_name": "Olga Org"}'),
  ('c0000000-0000-4000-8000-000000000023', 'nell.new@byui.edu', '{"full_name": "Nell New"}');

UPDATE public.profiles
SET
  guidelines_version = 1,
  guidelines_accepted_at = now()
WHERE id IN ('c0000000-0000-4000-8000-000000000021', 'c0000000-0000-4000-8000-000000000022');

-- Olga is going to each, as create_activity() would have made her.
INSERT INTO public.activities
  (
    id,
    organizer_id,
    category_id,
    title,
    starts_at,
    ends_at,
    location_name,
    status,
    cancelled_at,
    hidden_at,
    going_count
  )
VALUES
  (
    'f0000000-0000-4000-8000-000000000001',
    'c0000000-0000-4000-8000-000000000022',
    'games',
    'Tomorrow',
    now() + INTERVAL '1 day',
    NULL,
    'Here',
    'published',
    NULL,
    NULL,
    1
  ),
  (
    'f0000000-0000-4000-8000-000000000002',
    'c0000000-0000-4000-8000-000000000022',
    'games',
    'Cancelled',
    now() + INTERVAL '1 day',
    NULL,
    'Here',
    'cancelled',
    now(),
    NULL,
    1
  ),
  (
    'f0000000-0000-4000-8000-000000000003',
    'c0000000-0000-4000-8000-000000000022',
    'games',
    'Hidden',
    now() + INTERVAL '1 day',
    NULL,
    'Here',
    'published',
    NULL,
    now(),
    1
  ),
  (
    'f0000000-0000-4000-8000-000000000004',
    'c0000000-0000-4000-8000-000000000022',
    'games',
    'Ended an hour ago',
    now() - INTERVAL '2 hours',
    now() - INTERVAL '1 hour',
    'Here',
    'published',
    NULL,
    NULL,
    1
  ),
  (
    'f0000000-0000-4000-8000-000000000005',
    'c0000000-0000-4000-8000-000000000022',
    'games',
    'Started 2 hours ago',
    now() - INTERVAL '2 hours',
    NULL,
    'Here',
    'published',
    NULL,
    NULL,
    1
  ),
  (
    'f0000000-0000-4000-8000-000000000006',
    'c0000000-0000-4000-8000-000000000022',
    'games',
    'Started 4 hours ago',
    now() - INTERVAL '4 hours',
    NULL,
    'Here',
    'published',
    NULL,
    NULL,
    1
  );

INSERT INTO public.rsvps
  (activity_id, user_id, status)
SELECT
  id,
  organizer_id,
  'going'
FROM public.activities
WHERE id::text LIKE 'f0000000-%';

SET LOCAL ROLE authenticated;

SELECT set_config(
  'request.jwt.claims',
  '{"sub": "c0000000-0000-4000-8000-000000000021", "email": "rita.rsvp@byui.edu"}',
  TRUE
);

SELECT extensions.is(
  public.rsvp('f0000000-0000-4000-8000-000000000001', 'going'),
  2,
  'I''m in returns the going count, which now counts the member'
);

SELECT extensions.is(
  public.rsvp('f0000000-0000-4000-8000-000000000001', 'going'),
  2,
  'saying I''m in again changes nothing'
);

SELECT results_eq(
  $$select status from public.rsvps
  where activity_id = 'f0000000-0000-4000-8000-000000000001' and user_id = auth.uid()$$,
  $$values ('going'::text)$$,
  'a member has one RSVP to an activity'
);

SELECT extensions.is(
  public.rsvp('f0000000-0000-4000-8000-000000000001', 'not_going'),
  1,
  'Undo sets not_going, which isn''t counted'
);

SELECT extensions.is(
  public.rsvp('f0000000-0000-4000-8000-000000000001', 'going'),
  2,
  'and I''m in after that counts them again'
);

SELECT extensions.is(
  public.rsvp('f0000000-0000-4000-8000-000000000005', 'going'),
  2,
  'an activity that started 2 hours ago without an end time still takes RSVPs'
);

SELECT throws_ok(
  $$select public.rsvp('f0000000-0000-4000-8000-000000000002', 'going')$$,
  '22023',
  'ACTIVITY_CANCELLED',
  'a cancelled activity takes no RSVPs'
);

SELECT throws_ok(
  $$select public.rsvp('f0000000-0000-4000-8000-000000000003', 'going')$$,
  'P0002',
  'ACTIVITY_NOT_FOUND',
  'a hidden activity takes no RSVPs'
);

SELECT throws_ok(
  $$select public.rsvp('f0000000-0000-4000-8000-000000000004', 'going')$$,
  '22023',
  'ACTIVITY_OVER',
  'an activity that has ended takes no RSVPs'
);

SELECT throws_ok(
  $$select public.rsvp('f0000000-0000-4000-8000-000000000006', 'going')$$,
  '22023',
  'ACTIVITY_OVER',
  'without an end time, an activity is over 3 hours after it starts'
);

SELECT throws_ok(
  $$select public.rsvp(gen_random_uuid(), 'going')$$,
  'P0002',
  'ACTIVITY_NOT_FOUND',
  'an activity that doesn''t exist takes no RSVPs'
);

SELECT throws_ok(
  $$select public.rsvp('f0000000-0000-4000-8000-000000000001', 'perhaps')$$,
  '22023',
  'INVALID_STATUS',
  'an answer that isn''t one is refused'
);

SELECT throws_ok(
  $$insert into public.rsvps (activity_id, user_id, status)
  values ('f0000000-0000-4000-8000-000000000002', auth.uid(), 'going')$$,
  '42501',
  NULL,
  'members can''t write RSVPs except through rsvp()'
);

SELECT set_config(
  'request.jwt.claims',
  '{"sub": "c0000000-0000-4000-8000-000000000022", "email": "olga.org@byui.edu"}',
  TRUE
);

SELECT throws_ok(
  $$select public.rsvp('f0000000-0000-4000-8000-000000000001', 'not_going')$$,
  '22023',
  'ORGANIZER_GOING',
  'the organizer stays going'
);

SELECT set_config(
  'request.jwt.claims',
  '{"sub": "c0000000-0000-4000-8000-000000000023", "email": "nell.new@byui.edu"}',
  TRUE
);

SELECT throws_ok(
  $$select public.rsvp('f0000000-0000-4000-8000-000000000001', 'going')$$,
  '42501',
  'NOT_ACTIVE',
  'members who haven''t accepted the guidelines can''t RSVP'
);

RESET ROLE;

SELECT results_eq(
  $$select a.going_count, count(r.*)::integer from public.activities as a
  left join public.rsvps as r on r.activity_id = a.id and r.status = 'going'
  where a.id = 'f0000000-0000-4000-8000-000000000001' group by a.id$$,
  $$values (2, 2)$$,
  'the going count matches the going RSVPs'
);

SELECT ok(
  NOT has_function_privilege('anon', 'public.rsvp(uuid, text, integer)', 'execute'),
  'signed-out visitors can''t RSVP'
);

SELECT *
FROM finish();

ROLLBACK;
