-- The personal calendar feed (CAL-01). Run with `npm run db:test`.
BEGIN;

CREATE EXTENSION IF NOT EXISTS pgtap WITH SCHEMA extensions;

SELECT plan(9);

-- Tia organizes a picnic. Max and Dee are going. Dee is later suspended.
INSERT INTO auth.users
  (id, email, raw_user_meta_data)
VALUES
  ('c0000000-0000-4000-8000-000000000501', 'tia@byui.edu', '{"full_name": "Tia Host"}'),
  ('c0000000-0000-4000-8000-000000000502', 'max@byui.edu', '{"full_name": "Max Going"}'),
  ('c0000000-0000-4000-8000-000000000503', 'dee@byui.edu', '{"full_name": "Dee Going"}');

UPDATE public.profiles
SET
  guidelines_version = 1,
  guidelines_accepted_at = now()
WHERE id BETWEEN 'c0000000-0000-4000-8000-000000000501' AND 'c0000000-0000-4000-8000-000000000503';

INSERT INTO public.activities
  (id, organizer_id, category_id, title, starts_at, location_name)
VALUES
  (
    'f0000000-0000-4000-8000-000000000501',
    'c0000000-0000-4000-8000-000000000501',
    'food',
    'Picnic',
    now() + INTERVAL '2 days',
    'Park'
  );

INSERT INTO public.rsvps (activity_id, user_id, status, guest_count)
VALUES
  ('f0000000-0000-4000-8000-000000000501', 'c0000000-0000-4000-8000-000000000502', 'going', 0),
  ('f0000000-0000-4000-8000-000000000501', 'c0000000-0000-4000-8000-000000000503', 'going', 0);

-- Max makes a feed. The feed reads without signing in, so it's read as anon.
SET LOCAL ROLE authenticated;

SELECT set_config(
  'request.jwt.claims',
  '{"sub": "c0000000-0000-4000-8000-000000000502", "email": "max@byui.edu"}',
  TRUE
);

SELECT lives_ok($$select public.reset_calendar_feed('hash-1')$$, 'a member makes a calendar feed');

SET LOCAL ROLE anon;

SELECT results_eq(
  $$select count(*)::int from public.calendar_feed_events('hash-1')$$,
  $$values (1)$$,
  'the feed lists the activities the member is going to'
);

SELECT throws_ok(
  $$select count(*) from public.calendar_feed_events('no-such-hash')$$,
  'P0002',
  'FEED_NOT_FOUND',
  'an unknown token gets nothing'
);

-- Resetting makes a new link, and the old one stops working.
SET LOCAL ROLE authenticated;

SELECT lives_ok($$select public.reset_calendar_feed('hash-2')$$, 'a reset replaces the feed');

SET LOCAL ROLE anon;

SELECT throws_ok(
  $$select count(*) from public.calendar_feed_events('hash-1')$$,
  'P0002',
  'FEED_NOT_FOUND',
  'the old link stops working after a reset'
);

SELECT results_eq(
  $$select count(*)::int from public.calendar_feed_events('hash-2')$$,
  $$values (1)$$,
  'the new link works'
);

-- Dee makes a feed while active, and is then suspended. Their feed stops serving.
SET LOCAL ROLE authenticated;

SELECT set_config(
  'request.jwt.claims',
  '{"sub": "c0000000-0000-4000-8000-000000000503", "email": "dee@byui.edu"}',
  TRUE
);

SELECT lives_ok($$select public.reset_calendar_feed('hash-3')$$, 'Dee makes a feed while active');

RESET ROLE;

UPDATE public.profiles
SET status = 'suspended'
WHERE id = 'c0000000-0000-4000-8000-000000000503';

SET LOCAL ROLE anon;

SELECT throws_ok(
  $$select count(*) from public.calendar_feed_events('hash-3')$$,
  'P0002',
  'FEED_NOT_FOUND',
  'a suspended member''s feed serves nothing'
);

-- Max's feed can make 60 requests an hour. Max has made 2, so 58 more go through, then it's limited.
DO $$
BEGIN
  FOR i IN 1..58 LOOP
    PERFORM * FROM public.calendar_feed_events('hash-2');
  END LOOP;
END;
$$;

SELECT throws_ok(
  $$select count(*) from public.calendar_feed_events('hash-2')$$,
  '53400',
  'FEED_RATE_LIMITED',
  'a feed is rate limited after 60 requests an hour'
);

SELECT * FROM finish();
ROLLBACK;
