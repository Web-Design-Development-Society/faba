-- Scheduling games (LEAG-04). Run with `npm run db:test`.
BEGIN;

CREATE EXTENSION IF NOT EXISTS pgtap WITH SCHEMA extensions;

SELECT plan(23);

-- Oli runs a league with three teams. Mia is a member who isn't an organizer.
INSERT INTO auth.users
  (id, email, raw_user_meta_data)
VALUES
  ('c0000000-0000-4000-8000-000000001201', 'oli@byui.edu', '{"full_name": "Oli Scheduler"}'),
  ('c0000000-0000-4000-8000-000000001202', 'mia@byui.edu', '{"full_name": "Mia Member"}');

UPDATE public.profiles
SET
  guidelines_version = 1,
  guidelines_accepted_at = now()
WHERE id BETWEEN 'c0000000-0000-4000-8000-000000001201' AND 'c0000000-0000-4000-8000-000000001202';

SET LOCAL ROLE authenticated;

SELECT set_config(
  'request.jwt.claims',
  '{"sub": "c0000000-0000-4000-8000-000000001201", "email": "oli@byui.edu"}',
  TRUE
);

SELECT isnt(
  public.create_league('Pub Trivia', 'games', NULL, 'open'),
  NULL,
  'an organizer starts an open league'
);

SELECT lives_ok(
  $$select public.create_season(
    (select id from public.groups where slug like 'pub-trivia%'),
    'Summer 2026', date '2026-06-01', date '2026-08-31', 'teams', 2, 4, 3, 1, 0, true, true
  )$$,
  'a season is started'
);

SELECT set_config(
  'request.jwt.claims',
  '{"sub": "c0000000-0000-4000-8000-000000001202", "email": "mia@byui.edu"}',
  TRUE
);

SELECT lives_ok(
  $$select public.join_season(
    (select id from public.league_seasons where name = 'Summer 2026'), 'player'
  )$$,
  'Mia joins the league'
);

SELECT set_config(
  'request.jwt.claims',
  '{"sub": "c0000000-0000-4000-8000-000000001201", "email": "oli@byui.edu"}',
  TRUE
);

SELECT lives_ok(
  $$select public.create_team(
    (select id from public.league_seasons where name = 'Summer 2026'), 'Reds', '#ff0000'
  )$$,
  'a team is made'
);

SELECT lives_ok(
  $$select public.create_team(
    (select id from public.league_seasons where name = 'Summer 2026'), 'Blues', '#0000ff'
  )$$,
  'a second team is made'
);

SELECT lives_ok(
  $$select public.create_team(
    (select id from public.league_seasons where name = 'Summer 2026'), 'Greens', '#00ff00'
  )$$,
  'a third team is made'
);

-- Three teams, so three weeks: each round has a game and a bye. Tuesdays at 18:00, Boise time.
SELECT lives_ok(
  $$select public.schedule_round_robin(
    (select id from public.league_seasons where name = 'Summer 2026'),
    date '2026-06-01', 2, time '18:00', 'Gym A'
  )$$,
  'an organizer makes the round robin'
);

SELECT results_eq(
  $$select count(*) from public.league_games where activity_id is not null$$,
  $$values (3::bigint)$$,
  'each pair of teams plays once'
);

SELECT results_eq(
  $$select count(*) from public.league_games where away_team_id is null$$,
  $$values (3::bigint)$$,
  'a team sits out each round with three teams'
);

SELECT results_eq(
  $$select count(*) from public.league_games as g
    join public.league_teams as t on t.id = g.home_team_id or t.id = g.away_team_id
    where t.name = 'Reds' and g.away_team_id is not null$$,
  $$values (2::bigint)$$,
  'every team plays every other team'
);

SELECT results_eq(
  $$select count(*) from public.activities as a
    join public.league_games as g on g.activity_id = a.id
    where g.round = 1 and a.starts_at = timestamptz '2026-06-03 00:00:00+00'$$,
  $$values (1::bigint)$$,
  'the first game is on the first Tuesday, at 18:00 Boise time'
);

SELECT results_eq(
  $$select count(*) from public.activities as a
    join public.league_games as g on g.activity_id = a.id
    where a.visibility = 'group' and a.group_id is not null$$,
  $$values (3::bigint)$$,
  'each game is an activity in the league group'
);

SELECT throws_ok(
  $$select public.schedule_round_robin(
    (select id from public.league_seasons where name = 'Summer 2026'),
    date '2026-06-01', 2, time '18:00', 'Gym A'
  )$$,
  '22023',
  'SCHEDULE_EXISTS',
  'a season is scheduled once'
);

SELECT lives_ok(
  $$select public.update_game(
    (select id from public.league_games where activity_id is not null and round = 1),
    date '2026-06-09', time '19:00', 'Field 2'
  )$$,
  'an organizer changes one game'
);

SELECT results_eq(
  $$select a.location_name from public.activities as a
    join public.league_games as g on g.activity_id = a.id
    where g.round = 1$$,
  $$values ('Field 2'::text)$$,
  'the game''s place is changed'
);

SELECT throws_ok(
  $$select public.update_game(
    (select id from public.league_games where activity_id is null limit 1),
    date '2026-06-09', time '19:00', 'Field 2'
  )$$,
  '22023',
  'NOT_A_GAME',
  'a bye is not a game'
);

-- Mia isn't an organizer, so she can't change games.
SELECT set_config(
  'request.jwt.claims',
  '{"sub": "c0000000-0000-4000-8000-000000001202", "email": "mia@byui.edu"}',
  TRUE
);

SELECT throws_ok(
  $$select public.update_game(
    (select id from public.league_games where activity_id is not null and round = 1),
    date '2026-06-10', time '19:00', 'Field 3'
  )$$,
  '42501',
  'NOT_LEAGUE_ORGANIZER',
  'a member who is not an organizer can''t change a game'
);

SELECT set_config(
  'request.jwt.claims',
  '{"sub": "c0000000-0000-4000-8000-000000001201", "email": "oli@byui.edu"}',
  TRUE
);

-- A season with no teams has nothing to schedule.
SELECT lives_ok(
  $$select public.create_season(
    (select id from public.groups where slug like 'pub-trivia%'),
    'Fall 2026', date '2026-09-01', date '2026-11-30', 'teams', 2, 4, 3, 1, 0, true, false
  )$$,
  'a second season is started, not yet active'
);

SELECT throws_ok(
  $$select public.schedule_round_robin(
    (select id from public.league_seasons where name = 'Fall 2026'),
    date '2026-09-01', 2, time '18:00', 'Gym A'
  )$$,
  '22023',
  'NOT_ENOUGH_TEAMS',
  'a season needs two teams to schedule'
);

-- A short season, where the third week falls after it ends.
SELECT lives_ok(
  $$select public.create_season(
    (select id from public.groups where slug like 'pub-trivia%'),
    'Short', date '2026-06-01', date '2026-06-05', 'teams', 2, 4, 3, 1, 0, true, false
  )$$,
  'a short season is started'
);

SELECT lives_ok(
  $$select
      public.create_team((select id from public.league_seasons where name = 'Short'), 'Reds', '#ff0000'),
      public.create_team((select id from public.league_seasons where name = 'Short'), 'Blues', '#0000ff'),
      public.create_team((select id from public.league_seasons where name = 'Short'), 'Greens', '#00ff00')$$,
  'three teams are made for the short season'
);

SELECT throws_ok(
  $$select public.schedule_round_robin(
    (select id from public.league_seasons where name = 'Short'),
    date '2026-06-01', 2, time '18:00', 'Gym A'
  )$$,
  '22023',
  'SCHEDULE_PAST_SEASON',
  'a round robin fits inside the season'
);

SELECT results_eq(
  $$select count(*) from public.league_games as g
    join public.league_seasons as ls on ls.id = g.season_id
    where ls.name = 'Short'$$,
  $$values (0::bigint)$$,
  'a failed schedule leaves no games behind'
);

SELECT * FROM finish();

ROLLBACK;
