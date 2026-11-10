-- New people going, for organizers (NOTIF-06). Run with `npm run db:test`.
BEGIN;

CREATE EXTENSION IF NOT EXISTS pgtap WITH SCHEMA extensions;

SELECT plan(9);

-- Ora organizes pickleball, and Ann, Ben, Cy and Dee answer.
INSERT INTO auth.users
  (id, email, raw_user_meta_data)
SELECT
  ('c0000000-0000-4000-8000-00000000037' || n)::uuid,
  name || '@byui.edu',
  jsonb_build_object('full_name', name)
FROM (
  VALUES
    (1, 'ora'),
    (2, 'ann'),
    (3, 'ben'),
    (4, 'cy'),
    (5, 'dee')
) AS v (n, name);

UPDATE public.profiles
SET
  guidelines_version = 1,
  guidelines_accepted_at = now()
WHERE id::text LIKE 'c0000000-0000-4000-8000-00000000037_';

INSERT INTO public.activities
  (id, organizer_id, category_id, title, starts_at, location_name, going_count)
VALUES
  (
    'f0000000-0000-4000-8000-000000000371',
    'c0000000-0000-4000-8000-000000000371',
    'sports',
    'Pickleball',
    now() + INTERVAL '1 day',
    'Hart courts',
    1
  );

INSERT INTO public.rsvps
  (activity_id, user_id, status)
VALUES
  ('f0000000-0000-4000-8000-000000000371', 'c0000000-0000-4000-8000-000000000371', 'going');

-- Answers as Ora (1), Ann (2), Ben (3), Cy (4) or Dee (5).
CREATE FUNCTION pg_temp.answer(member text, status text)
RETURNS void
LANGUAGE sql
AS $$
  SELECT set_config(
    'request.jwt.claims',
    json_build_object(
      'sub',
      'c0000000-0000-4000-8000-00000000037' || member,
      'email',
      member || '@byui.edu'
    )::text,
    TRUE
  );
  SELECT public.rsvp('f0000000-0000-4000-8000-000000000371', status);
$$;

-- Ora's new_attendees notifications, read as the database owner, whoever is signed in.
CREATE FUNCTION pg_temp.batches()
RETURNS TABLE (title text, count INTEGER, unread BOOLEAN, actor uuid)
LANGUAGE sql
SECURITY DEFINER
AS $$
  SELECT
    n.payload->>'title',
    (n.payload->>'count')::INTEGER,
    n.read_at IS NULL,
    n.actor_id
  FROM public.notifications AS n
  WHERE n.recipient_id = 'c0000000-0000-4000-8000-000000000371' AND n.type = 'new_attendees'
  ORDER BY n.created_at;
$$;

GRANT EXECUTE ON FUNCTION pg_temp.answer(text, text), pg_temp.batches() TO authenticated;

SET LOCAL ROLE authenticated;

SELECT pg_temp.answer('2', 'maybe');

SELECT is_empty($$select from pg_temp.batches()$$, 'a maybe doesn''t tell the organizer');

SELECT pg_temp.answer('2', 'going');

SELECT results_eq(
  $$select * from pg_temp.batches()$$,
  $$values (
    'Pickleball',
    1,
    true,
    'c0000000-0000-4000-8000-000000000372'::uuid
  )$$,
  'I''m in tells the organizer, unread'
);

SELECT pg_temp.answer('3', 'going');

SELECT pg_temp.answer('4', 'going');

SELECT results_eq(
  $$select count, unread, actor from pg_temp.batches()$$,
  $$values (3, true, 'c0000000-0000-4000-8000-000000000374'::uuid)$$,
  'more in the same hour count in the same one'
);

SELECT pg_temp.answer('3', 'not_going');

SELECT results_eq(
  $$select count from pg_temp.batches()$$,
  $$values (3)$$,
  'leaving doesn''t change it'
);

SELECT set_config(
  'request.jwt.claims',
  '{"sub": "c0000000-0000-4000-8000-000000000371", "email": "ora@byui.edu"}',
  TRUE
);

SELECT public.mark_notifications_read();

SELECT pg_temp.answer('5', 'going');

SELECT results_eq(
  $$select count, unread from pg_temp.batches()$$,
  $$values (1, true)$$,
  'once read, the next one starts again at 1'
);

-- An hour later, it's a new one.
RESET ROLE;

UPDATE public.notifications
SET dedupe_key = 'new_attendees:f0000000-0000-4000-8000-000000000371:2000-01-01T00'
WHERE type = 'new_attendees';

SET LOCAL ROLE authenticated;

SELECT pg_temp.answer('3', 'going');

SELECT results_eq(
  $$select count(*)::integer from pg_temp.batches()$$,
  $$values (2)$$,
  'the next hour makes another'
);

SELECT set_config(
  'request.jwt.claims',
  '{"sub": "c0000000-0000-4000-8000-000000000371", "email": "ora@byui.edu"}',
  TRUE
);

SELECT public.mute_activity('f0000000-0000-4000-8000-000000000371', TRUE);

SELECT pg_temp.answer('2', 'not_going');

SELECT pg_temp.answer('2', 'going');

SELECT results_eq(
  $$select count(*)::integer, sum(count)::integer from pg_temp.batches()$$,
  $$values (2, 2)$$,
  'muting the activity turns it off'
);

SELECT set_config(
  'request.jwt.claims',
  '{"sub": "c0000000-0000-4000-8000-000000000372", "email": "ann@byui.edu"}',
  TRUE
);

SELECT is_empty(
  $$select from public.notifications where type = 'new_attendees'$$,
  'members going don''t read the organizer''s'
);

SELECT set_config(
  'request.jwt.claims',
  '{"sub": "c0000000-0000-4000-8000-000000000371", "email": "ora@byui.edu"}',
  TRUE
);

SELECT results_eq(
  $$select count(*)::integer from public.notifications where type = 'new_attendees'$$,
  $$values (2)$$,
  'while the organizer does'
);

SELECT *
FROM finish();

ROLLBACK;
