-- A picture when posting (MEDIA-02): a series' dates share its cover. Run with `npm run db:test`.
BEGIN;

CREATE EXTENSION IF NOT EXISTS pgtap WITH SCHEMA extensions;

SELECT plan(12);

-- Rae posts weekly pickleball, and Ned is another member.
INSERT INTO auth.users
  (id, email, raw_user_meta_data)
SELECT
  ('c0000000-0000-4000-8000-00000000052' || n)::uuid,
  name || '@byui.edu',
  jsonb_build_object('full_name', name)
FROM (
  VALUES
    (1, 'rae'),
    (2, 'ned')
) AS v (n, name);

UPDATE public.profiles
SET
  guidelines_version = 1,
  guidelines_accepted_at = now()
WHERE id::text LIKE 'c0000000-0000-4000-8000-00000000052_';

CREATE TABLE pg_temp.ids (name text PRIMARY KEY, id uuid);

GRANT ALL ON pg_temp.ids TO authenticated;

-- Rae
SET LOCAL ROLE authenticated;

SELECT set_config(
  'request.jwt.claims',
  '{"sub": "c0000000-0000-4000-8000-000000000521", "email": "rae@byui.edu"}',
  TRUE
);

INSERT INTO pg_temp.ids
VALUES
  (
    'first',
    public.create_series(
      title => 'Tuesday pickleball',
      category_id => 'sports',
      starts_at => date_trunc('hour', now()) + INTERVAL '1 day 2 hours',
      location_name => 'Hart courts',
      freq => 'weekly'
    )
  );

INSERT INTO pg_temp.ids
VALUES
  (
    'one-off',
    public.create_activity(
      title => 'Board game night',
      category_id => 'games',
      starts_at => date_trunc('hour', now()) + INTERVAL '2 days',
      location_name => 'Library'
    )
  );

-- The third date has a picture of its own, from its page.
INSERT INTO pg_temp.ids
SELECT
  'third',
  a.id
FROM public.activities AS a
WHERE
  a.series_id = (
    SELECT series_id
    FROM public.activities
    WHERE id = (SELECT id FROM pg_temp.ids WHERE name = 'first')
  )
ORDER BY a.starts_at
OFFSET 2
LIMIT 1;

INSERT INTO pg_temp.ids
VALUES
  (
    'own',
    public.set_activity_cover(
      (SELECT id FROM pg_temp.ids WHERE name = 'third'),
      'activities/own-picture',
      'image/jpeg',
      1000,
      'Our court'
    )
  );

INSERT INTO pg_temp.ids
VALUES
  (
    'picture',
    public.set_activity_cover(
      (SELECT id FROM pg_temp.ids WHERE name = 'first'),
      'activities/pickleball',
      'image/jpeg',
      2000,
      'Paddles on a court'
    )
  );

CREATE VIEW pg_temp.dates AS
  SELECT
    a.id,
    a.cover_image_id,
    a.series_id
  FROM public.activities AS a
  WHERE
    a.series_id = (
      SELECT series_id
      FROM public.activities
      WHERE id = (SELECT id FROM pg_temp.ids WHERE name = 'first')
    );

GRANT SELECT ON pg_temp.dates TO authenticated;

SELECT cmp_ok(
  (SELECT count(*)::INTEGER FROM pg_temp.dates),
  '>=',
  4,
  'the series has its first dates'
);

-- Ned
SELECT set_config(
  'request.jwt.claims',
  '{"sub": "c0000000-0000-4000-8000-000000000522", "email": "ned@byui.edu"}',
  TRUE
);

SELECT throws_ok(
  format(
    'select public.share_cover_with_series(%L)',
    (SELECT id FROM pg_temp.ids WHERE name = 'first')
  ),
  '42501',
  'NOT_ORGANIZER',
  'only the organizer shares a cover with the series'
);

-- Rae
SELECT set_config(
  'request.jwt.claims',
  '{"sub": "c0000000-0000-4000-8000-000000000521", "email": "rae@byui.edu"}',
  TRUE
);

SELECT results_eq(
  format(
    'select public.share_cover_with_series(%L)',
    (SELECT id FROM pg_temp.ids WHERE name = 'first')
  ),
  format('values (%s)', (SELECT count(*) - 2 FROM pg_temp.dates)),
  'the other dates get the cover, but for one with its own'
);

SELECT results_eq(
  $$select count(*)::integer from pg_temp.dates
  where cover_image_id = (select id from pg_temp.ids where name = 'picture')$$,
  $$select count(*)::integer - 1 from pg_temp.dates$$,
  'every date shows the picture'
);

SELECT results_eq(
  $$select cover_image_id from pg_temp.dates where id = (select id from pg_temp.ids where name = 'third')$$,
  $$select id from pg_temp.ids where name = 'own'$$,
  'and the third date keeps its own'
);

SELECT results_eq(
  $$select count(*)::integer from public.images
  where id = (select id from pg_temp.ids where name = 'picture')$$,
  $$values (1)$$,
  'the dates share one picture'
);

SELECT results_eq(
  format(
    'select public.share_cover_with_series(%L)',
    (SELECT id FROM pg_temp.ids WHERE name = 'one-off')
  ),
  $$values (0)$$,
  'an activity in no series has nothing to share'
);

SELECT throws_ok(
  'update public.activity_series set cover_image_id = null',
  '42501',
  NULL,
  'members change a series'' cover only through the function'
);

RESET ROLE;

SELECT results_eq(
  $$select s.cover_image_id from public.activity_series as s
  where s.id = (select series_id from pg_temp.dates limit 1)$$,
  $$select id from pg_temp.ids where name = 'picture'$$,
  'the series keeps the picture'
);

-- Weeks later, the series adds its next dates.
SELECT cmp_ok(
  private.generate_occurrences(
    (SELECT series_id FROM pg_temp.dates LIMIT 1),
    now() + INTERVAL '5 weeks'
  ),
  '>',
  0,
  'the series adds dates as it rolls on'
);

SELECT is_empty(
  $$select id from pg_temp.dates
  where cover_image_id is distinct from (select id from pg_temp.ids where name = 'picture')
    and id <> (select id from pg_temp.ids where name = 'third')$$,
  'and they show the picture too'
);

-- Ned sees the picture on a later date, which belongs to the first date.
SET LOCAL ROLE authenticated;

SELECT set_config(
  'request.jwt.claims',
  '{"sub": "c0000000-0000-4000-8000-000000000522", "email": "ned@byui.edu"}',
  TRUE
);

SELECT results_eq(
  $$select i.alt from public.activities as a
  join public.images as i on i.id = a.cover_image_id
  where a.series_id = (select series_id from pg_temp.dates limit 1)
  order by a.starts_at desc
  limit 1$$,
  $$values ('Paddles on a court'::text)$$,
  'another member sees it on the last date'
);

SELECT *
FROM finish();

ROLLBACK;
