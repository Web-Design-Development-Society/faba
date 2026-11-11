-- The waitlist (RSVP-07). Run with `npm run db:test`.
BEGIN;

CREATE EXTENSION IF NOT EXISTS pgtap WITH SCHEMA extensions;

SELECT plan(27);

-- Rae organizes, and Gid, Mel, Sue and Tom come along.
INSERT INTO auth.users
  (id, email, raw_user_meta_data)
SELECT
  ('c0000000-0000-4000-8000-00000000050' || n)::uuid,
  name || '@byui.edu',
  jsonb_build_object('full_name', name)
FROM (
  VALUES
    (1, 'rae'),
    (2, 'gid'),
    (3, 'mel'),
    (4, 'sue'),
    (5, 'tom')
) AS v (n, name);

UPDATE public.profiles
SET
  guidelines_version = 1,
  guidelines_accepted_at = now()
WHERE id::text LIKE 'c0000000-0000-4000-8000-00000000050_';

-- Tea for 2 and dinner for 3, where guests are welcome, both in 2 days. Rae has a spot in each.
INSERT INTO public.activities
  (
    id,
    organizer_id,
    category_id,
    title,
    starts_at,
    location_name,
    going_count,
    capacity,
    guests_allowed
  )
VALUES
  (
    'f0000000-0000-4000-8000-000000000501',
    'c0000000-0000-4000-8000-000000000501',
    'food',
    'Tiny tea',
    now() + INTERVAL '2 days',
    'The Crossroads',
    1,
    2,
    FALSE
  ),
  (
    'f0000000-0000-4000-8000-000000000502',
    'c0000000-0000-4000-8000-000000000501',
    'food',
    'Small dinner',
    now() + INTERVAL '2 days',
    'The Crossroads',
    1,
    3,
    TRUE
  );

INSERT INTO public.rsvps
  (activity_id, user_id, status)
VALUES
  ('f0000000-0000-4000-8000-000000000501', 'c0000000-0000-4000-8000-000000000501', 'going'),
  ('f0000000-0000-4000-8000-000000000502', 'c0000000-0000-4000-8000-000000000501', 'going');

SET LOCAL ROLE authenticated;

-- Signs in as one of them.
CREATE FUNCTION pg_temp.as_member(n INTEGER)
RETURNS text
LANGUAGE sql
AS $$
  SELECT set_config(
    'request.jwt.claims',
    jsonb_build_object(
      'sub',
      'c0000000-0000-4000-8000-00000000050' || n,
      'email',
      (ARRAY['rae', 'gid', 'mel', 'sue', 'tom'])[n] || '@byui.edu'
    )::text,
    TRUE
  );
$$;

-- The signed-in member's answer to the tea.
CREATE FUNCTION pg_temp.answer()
RETURNS text
LANGUAGE sql
AS $$
  SELECT r.status
  FROM public.rsvps AS r
  WHERE r.activity_id = 'f0000000-0000-4000-8000-000000000501' AND r.user_id = auth.uid();
$$;

SELECT pg_temp.as_member(2);

SELECT results_eq(
  $$select public.rsvp('f0000000-0000-4000-8000-000000000501', 'going')$$,
  $$values (2)$$,
  'someone takes the last spot'
);

SELECT pg_temp.as_member(3);

SELECT throws_ok(
  $$select public.rsvp('f0000000-0000-4000-8000-000000000501', 'going')$$,
  '22023',
  'ACTIVITY_FULL',
  'I''m in still fails when it''s full'
);

SELECT results_eq(
  $$select public.rsvp('f0000000-0000-4000-8000-000000000501', 'waitlisted')$$,
  $$values (2)$$,
  'Join waitlist works, and takes no spot'
);

SELECT pg_temp.as_member(4);

SELECT lives_ok(
  $$select public.rsvp('f0000000-0000-4000-8000-000000000501', 'waitlisted')$$,
  'a second member waits'
);

SELECT results_eq(
  $$select pg_temp.answer(), public.waitlist_position('f0000000-0000-4000-8000-000000000501')$$,
  $$values ('waitlisted'::text, 2)$$,
  'and is #2'
);

SELECT results_eq(
  $$
    select count(*)::integer
    from public.rsvps
    where activity_id = 'f0000000-0000-4000-8000-000000000501' and status = 'waitlisted'
  $$,
  $$values (1)$$,
  'members can''t read who else is waiting'
);

SELECT pg_temp.as_member(3);

SELECT lives_ok(
  $$select public.rsvp('f0000000-0000-4000-8000-000000000501', 'waitlisted')$$,
  'joining again'
);

SELECT results_eq(
  $$select public.waitlist_position('f0000000-0000-4000-8000-000000000501')$$,
  $$values (1)$$,
  'keeps their place'
);

SELECT pg_temp.as_member(2);

SELECT results_eq(
  $$select public.waitlist_position('f0000000-0000-4000-8000-000000000501')$$,
  $$values (null::integer)$$,
  'someone going has no place in line'
);

SELECT results_eq(
  $$select public.rsvp('f0000000-0000-4000-8000-000000000501', 'not_going')$$,
  $$values (2)$$,
  'when someone leaves, the spot is taken again at once'
);

SELECT pg_temp.as_member(3);

SELECT results_eq(
  $$select pg_temp.answer(), public.waitlist_position('f0000000-0000-4000-8000-000000000501')$$,
  $$values ('going'::text, null::integer)$$,
  'by whoever waited longest'
);

SELECT results_eq(
  $$
    select n.read_at is null, n.actor_id is null, n.payload ->> 'title'
    from public.notifications as n
    where n.type = 'rsvp_promoted'
  $$,
  $$values (true, true, 'Tiny tea'::text)$$,
  'who gets an unread notification that doesn''t say who left'
);

SELECT pg_temp.as_member(4);

SELECT results_eq(
  $$select pg_temp.answer(), public.waitlist_position('f0000000-0000-4000-8000-000000000501')$$,
  $$values ('waitlisted'::text, 1)$$,
  'and the next in line moves up'
);

-- The organizer makes room for 2 more.
SELECT pg_temp.as_member(1);

SELECT lives_ok(
  $$
    select public.update_activity(
      'f0000000-0000-4000-8000-000000000501',
      '{"capacity": 4}',
      (select version from public.activities where id = 'f0000000-0000-4000-8000-000000000501')
    )
  $$,
  'the organizer adds spots'
);

SELECT results_eq(
  $$
    select a.going_count, (
      select r.status
      from public.rsvps as r
      where r.activity_id = a.id and r.user_id = 'c0000000-0000-4000-8000-000000000504'
    )
    from public.activities as a
    where a.id = 'f0000000-0000-4000-8000-000000000501'
  $$,
  $$values (3, 'going'::text)$$,
  'and the waitlist takes one'
);

SELECT pg_temp.as_member(5);

SELECT results_eq(
  $$select public.rsvp('f0000000-0000-4000-8000-000000000501', 'waitlisted'), pg_temp.answer()$$,
  $$values (4, 'going'::text)$$,
  'Join waitlist with a spot open is going'
);

-- Promotion stops 1 hour before the start.
SELECT pg_temp.as_member(2);

SELECT lives_ok(
  $$select public.rsvp('f0000000-0000-4000-8000-000000000501', 'waitlisted')$$,
  'someone waits for the full activity'
);

RESET ROLE;

UPDATE public.activities
SET starts_at = now() + INTERVAL '30 minutes'
WHERE id = 'f0000000-0000-4000-8000-000000000501';

SET LOCAL ROLE authenticated;

SELECT pg_temp.as_member(5);

SELECT results_eq(
  $$select public.rsvp('f0000000-0000-4000-8000-000000000501', 'not_going')$$,
  $$values (3)$$,
  'a spot that opens in the last hour stays open'
);

SELECT pg_temp.as_member(2);

SELECT results_eq(
  $$select pg_temp.answer(), public.rsvp('f0000000-0000-4000-8000-000000000501', 'going')$$,
  $$values ('waitlisted'::text, 4)$$,
  'for whoever says I''m in, the one waiting too'
);

SELECT results_eq(
  $$
    select r.status, r.waitlisted_at is null
    from public.rsvps as r
    where r.activity_id = 'f0000000-0000-4000-8000-000000000501' and r.user_id = auth.uid()
  $$,
  $$values ('going'::text, true)$$,
  'who then isn''t waiting'
);

-- Dinner for 3: Rae, Gid and Gid's guest. Mel and Sue wait.
SELECT lives_ok(
  $$select public.rsvp('f0000000-0000-4000-8000-000000000502', 'going', 1)$$,
  'someone brings a guest, which fills it'
);

SELECT pg_temp.as_member(3);

SELECT lives_ok(
  $$select public.rsvp('f0000000-0000-4000-8000-000000000502', 'waitlisted', 1)$$,
  'someone waits, and their guest doesn''t'
);

SELECT pg_temp.as_member(4);

SELECT lives_ok(
  $$select public.rsvp('f0000000-0000-4000-8000-000000000502', 'waitlisted')$$,
  'and a second'
);

SELECT results_eq(
  $$select public.rsvp('f0000000-0000-4000-8000-000000000502', 'maybe')$$,
  $$values (2)$$,
  'who becomes a maybe, which leaves the waitlist'
);

SELECT pg_temp.as_member(2);

SELECT results_eq(
  $$select public.rsvp('f0000000-0000-4000-8000-000000000502', 'going', 0)$$,
  $$values (3)$$,
  'bringing fewer guests opens a spot for the waitlist'
);

RESET ROLE;

SELECT results_eq(
  $$
    select
      a.going_count,
      a.guest_total,
      a.maybe_count,
      (select string_agg(r.status || ':' || r.guest_count, ' ' order by r.user_id)
        from public.rsvps as r where r.activity_id = a.id)
    from public.activities as a
    where a.id = 'f0000000-0000-4000-8000-000000000502'
  $$,
  $$values (3, 0, 1, 'going:0 going:0 going:0 maybe:0'::text)$$,
  'and the counts add up'
);

-- Leaving takes the account's place in line with it.
UPDATE public.activities
SET
  capacity = 3,
  starts_at = now() + INTERVAL '2 days'
WHERE id = 'f0000000-0000-4000-8000-000000000501';

SELECT results_eq(
  $$
    select a.going_count, count(*) filter (where r.status = 'waitlisted')::integer
    from public.activities as a
    join public.rsvps as r on r.activity_id = a.id
    where a.id = 'f0000000-0000-4000-8000-000000000501'
    group by a.going_count
  $$,
  $$values (4, 0)$$,
  'lowering the capacity leaves everyone going'
);

SELECT *
FROM finish();

ROLLBACK;
