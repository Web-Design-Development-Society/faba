-- Leagues and seasons (LEAG-01). Run with `npm run db:test`.
BEGIN;

CREATE EXTENSION IF NOT EXISTS pgtap WITH SCHEMA extensions;

SELECT plan(10);

-- Oli makes a league and runs its seasons. Mia is a member who isn't an organizer.
INSERT INTO auth.users
  (id, email, raw_user_meta_data)
VALUES
  ('c0000000-0000-4000-8000-000000000901', 'oli@byui.edu', '{"full_name": "Oli League"}'),
  ('c0000000-0000-4000-8000-000000000902', 'mia@byui.edu', '{"full_name": "Mia Player"}');

UPDATE public.profiles
SET
  guidelines_version = 1,
  guidelines_accepted_at = now()
WHERE id BETWEEN 'c0000000-0000-4000-8000-000000000901' AND 'c0000000-0000-4000-8000-000000000902';

SET LOCAL ROLE authenticated;

SELECT set_config(
  'request.jwt.claims',
  '{"sub": "c0000000-0000-4000-8000-000000000901", "email": "oli@byui.edu"}',
  TRUE
);

SELECT isnt(
  public.create_league('Summer Pickleball', 'sports'),
  NULL,
  'a member can start a league'
);

SELECT results_eq(
  $$select kind from public.groups where slug like 'summer-pickleball%'$$,
  $$values ('league'::text)$$,
  'a league is a group of kind league'
);

SELECT lives_ok(
  $$select public.create_season(
    (select id from public.groups where slug like 'summer-pickleball%'),
    'Summer 2026', date '2026-06-01', date '2026-08-31', 'teams', 2, 4, 3, 1, 0, true, true
  )$$,
  'an organizer starts a season'
);

SELECT throws_ok(
  $$select public.create_season(
    (select id from public.groups where slug like 'summer-pickleball%'),
    'Fall 2026', date '2026-09-01', date '2026-11-30', 'teams', 2, 4, 3, 1, 0, true, true
  )$$,
  '22023',
  'SEASON_ALREADY_ACTIVE',
  'a league has one active season at a time'
);

SELECT throws_ok(
  $$select public.create_season(
    (select id from public.groups where slug like 'summer-pickleball%'),
    'Ladder', date '2026-09-01', date '2026-11-30', 'ladder', 1, 3, 3, 1, 0, true, false
  )$$,
  '23514',
  NULL,
  'a ladder is for one person at a time'
);

-- Mia isn't an organizer, so she can't start one.
SELECT set_config(
  'request.jwt.claims',
  '{"sub": "c0000000-0000-4000-8000-000000000902", "email": "mia@byui.edu"}',
  TRUE
);

SELECT throws_ok(
  $$select public.create_season(
    (select id from public.groups where slug like 'summer-pickleball%'),
    'Sneaky', date '2026-09-01', date '2026-11-30', 'teams', 2, 4, 3, 1, 0, true, false
  )$$,
  '42501',
  'NOT_LEAGUE_ORGANIZER',
  'only an organizer starts a season'
);

SELECT results_eq(
  $$select count(*)::int from public.league_seasons$$,
  $$values (1)$$,
  'a member sees the seasons of a league'
);

-- A group that isn't a league has no seasons.
SELECT set_config(
  'request.jwt.claims',
  '{"sub": "c0000000-0000-4000-8000-000000000901", "email": "oli@byui.edu"}',
  TRUE
);

SELECT public.create_group('Board Game Crew', 'sports');

SELECT throws_ok(
  $$select public.create_season(
    (select id from public.groups where slug like 'board-game-crew%'),
    'Not a league', date '2026-09-01', date '2026-11-30', 'teams', 2, 4, 3, 1, 0, true, false
  )$$,
  '22023',
  'NOT_A_LEAGUE',
  'only a league has seasons'
);

SELECT lives_ok(
  $$select public.create_season(
    (select id from public.groups where slug like 'summer-pickleball%'),
    'Ladder 2026', date '2026-09-01', date '2026-11-30', 'ladder', 1, 1, 3, 1, 0, true, false
  )$$,
  'an organizer adds an inactive ladder season'
);

SELECT results_eq(
  $$select count(*)::int from public.league_seasons$$,
  $$values (2)$$,
  'both seasons are kept'
);

RESET ROLE;

SELECT * FROM finish();
ROLLBACK;
