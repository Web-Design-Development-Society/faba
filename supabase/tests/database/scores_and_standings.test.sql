-- Scores and standings (LEAG-05). Run with `npm run db:test`.
BEGIN;

CREATE EXTENSION IF NOT EXISTS pgtap WITH SCHEMA extensions;

SELECT plan(27);

-- Oli runs a league. Mia captains Reds and Pat captains Blues, and Quinn is a member who isn't on
-- either team.
INSERT INTO auth.users
  (id, email, raw_user_meta_data)
VALUES
  ('c0000000-0000-4000-8000-000000001301', 'oli@byui.edu', '{"full_name": "Oli Referee"}'),
  ('c0000000-0000-4000-8000-000000001302', 'mia@byui.edu', '{"full_name": "Mia Captain"}'),
  ('c0000000-0000-4000-8000-000000001303', 'pat@byui.edu', '{"full_name": "Pat Captain"}'),
  ('c0000000-0000-4000-8000-000000001304', 'quinn@byui.edu', '{"full_name": "Quinn Fan"}');

UPDATE public.profiles
SET
  guidelines_version = 1,
  guidelines_accepted_at = now()
WHERE id BETWEEN 'c0000000-0000-4000-8000-000000001301' AND 'c0000000-0000-4000-8000-000000001304';

SET LOCAL ROLE authenticated;

SELECT set_config(
  'request.jwt.claims',
  '{"sub": "c0000000-0000-4000-8000-000000001301", "email": "oli@byui.edu"}',
  TRUE
);

SELECT isnt(
  public.create_league('Cornhole League', 'sports', NULL, 'open'),
  NULL,
  'an organizer starts an open league'
);

SELECT lives_ok(
  $$select public.create_season(
    (select id from public.groups where slug like 'cornhole-league%'),
    'Summer 2026', date '2026-06-01', date '2026-08-31', 'teams', 2, 4, 3, 1, 0, true, true
  )$$,
  'a season is started'
);

SELECT set_config(
  'request.jwt.claims',
  '{"sub": "c0000000-0000-4000-8000-000000001302", "email": "mia@byui.edu"}',
  TRUE
);

SELECT lives_ok(
  $$select public.join_season((select id from public.league_seasons where name = 'Summer 2026'), 'player')$$,
  'Mia signs up as a player'
);

SELECT set_config(
  'request.jwt.claims',
  '{"sub": "c0000000-0000-4000-8000-000000001303", "email": "pat@byui.edu"}',
  TRUE
);

SELECT lives_ok(
  $$select public.join_season((select id from public.league_seasons where name = 'Summer 2026'), 'player')$$,
  'Pat signs up as a player'
);

SELECT set_config(
  'request.jwt.claims',
  '{"sub": "c0000000-0000-4000-8000-000000001301", "email": "oli@byui.edu"}',
  TRUE
);

SELECT lives_ok(
  $$select public.create_team((select id from public.league_seasons where name = 'Summer 2026'), 'Reds', '#ff0000')$$,
  'a team is made'
);

SELECT lives_ok(
  $$select public.create_team((select id from public.league_seasons where name = 'Summer 2026'), 'Blues', '#0000ff')$$,
  'a second team is made'
);

SELECT lives_ok(
  $$select public.assign_player((select id from public.league_seasons where name = 'Summer 2026'),
    'c0000000-0000-4000-8000-000000001302', (select id from public.league_teams where name = 'Reds'))$$,
  'Mia is put on Reds'
);

SELECT lives_ok(
  $$select public.assign_player((select id from public.league_seasons where name = 'Summer 2026'),
    'c0000000-0000-4000-8000-000000001303', (select id from public.league_teams where name = 'Blues'))$$,
  'Pat is put on Blues'
);

SELECT lives_ok(
  $$select public.update_team((select id from public.league_teams where name = 'Reds'), 'Reds', '#ff0000',
    'c0000000-0000-4000-8000-000000001302')$$,
  'Mia captains Reds'
);

SELECT lives_ok(
  $$select public.update_team((select id from public.league_teams where name = 'Blues'), 'Blues', '#0000ff',
    'c0000000-0000-4000-8000-000000001303')$$,
  'Pat captains Blues'
);

SELECT lives_ok(
  $$select public.schedule_round_robin((select id from public.league_seasons where name = 'Summer 2026'),
    date '2026-06-01', 2, time '18:00', 'Gym A')$$,
  'two teams make one game'
);

-- Mia reports the game as a captain. A score has to be in range.
SELECT set_config(
  'request.jwt.claims',
  '{"sub": "c0000000-0000-4000-8000-000000001302", "email": "mia@byui.edu"}',
  TRUE
);

SELECT throws_ok(
  $$select public.report_score((select id from public.league_games where activity_id is not null), 1000, 1)$$,
  '22023',
  'INVALID_SCORE',
  'a score is between 0 and 999'
);

SELECT lives_ok(
  $$select public.report_score((select id from public.league_games where activity_id is not null), 3, 1)$$,
  'a captain reports the score'
);

SELECT results_eq(
  $$select status from public.league_games where activity_id is not null$$,
  $$values ('reported'::text)$$,
  'a reported score waits for confirmation'
);

-- The team that reported can't confirm its own score.
SELECT throws_ok(
  $$select public.confirm_score((select id from public.league_games where activity_id is not null))$$,
  '42501',
  'NOT_OPPOSING_CAPTAIN',
  'the reporting captain can''t confirm it'
);

SELECT set_config(
  'request.jwt.claims',
  '{"sub": "c0000000-0000-4000-8000-000000001301", "email": "oli@byui.edu"}',
  TRUE
);

SELECT throws_ok(
  $$select public.report_score((select id from public.league_games where activity_id is not null), 0, 0)$$,
  '42501',
  'NOT_CAPTAIN',
  'an organizer who captains no team can''t report a score'
);

SELECT set_config(
  'request.jwt.claims',
  '{"sub": "c0000000-0000-4000-8000-000000001303", "email": "pat@byui.edu"}',
  TRUE
);

SELECT lives_ok(
  $$select public.confirm_score((select id from public.league_games where activity_id is not null))$$,
  'the other captain confirms the score'
);

SELECT results_eq(
  $$select status from public.league_games where activity_id is not null$$,
  $$values ('confirmed'::text)$$,
  'a confirmed score is final'
);

SELECT results_eq(
  $$select won, points, differential from public.season_standings(
      (select id from public.league_seasons where name = 'Summer 2026')
    ) where team_name = 'Reds'$$,
  $$values (1, 3, 2)$$,
  'the winner has a win, its points and its margin'
);

SELECT results_eq(
  $$select lost, points, differential from public.season_standings(
      (select id from public.league_seasons where name = 'Summer 2026')
    ) where team_name = 'Blues'$$,
  $$values (1, 0, -2)$$,
  'the loser has a loss and a negative margin'
);

-- Pat isn't an organizer, so Pat can't override a score.
SELECT throws_ok(
  $$select public.override_score((select id from public.league_games where activity_id is not null), 2, 2, 'Scorer error')$$,
  '42501',
  'NOT_LEAGUE_ORGANIZER',
  'a captain can''t override a score'
);

SELECT set_config(
  'request.jwt.claims',
  '{"sub": "c0000000-0000-4000-8000-000000001301", "email": "oli@byui.edu"}',
  TRUE
);

SELECT lives_ok(
  $$select public.override_score((select id from public.league_games where activity_id is not null), 2, 2, 'Scorer error')$$,
  'an organizer overrides the score'
);

SELECT results_eq(
  $$select tied, points from public.season_standings(
      (select id from public.league_seasons where name = 'Summer 2026')
    ) where team_name = 'Reds'$$,
  $$values (1, 1)$$,
  'an overridden score counts in the standings'
);

RESET ROLE;

SELECT results_eq(
  $$select count(*) from private.audit_log
    where action = 'override_score' and reason = 'Scorer error'$$,
  $$values (1::bigint)$$,
  'the override is audit-logged with its reason'
);

SET LOCAL ROLE authenticated;

SELECT lives_ok(
  $$select public.forfeit_game((select id from public.league_games where activity_id is not null),
    (select id from public.league_teams where name = 'Reds'))$$,
  'an organizer records a forfeit'
);

SELECT results_eq(
  $$select won, points, differential from public.season_standings(
      (select id from public.league_seasons where name = 'Summer 2026')
    ) where team_name = 'Blues'$$,
  $$values (1, 3, 0)$$,
  'a forfeit is a win for the other team, with no margin'
);

SELECT set_config(
  'request.jwt.claims',
  '{"sub": "c0000000-0000-4000-8000-000000001302", "email": "mia@byui.edu"}',
  TRUE
);

SELECT throws_ok(
  $$select public.report_score((select id from public.league_games where activity_id is not null), 2, 0)$$,
  '22023',
  'GAME_LOCKED',
  'a forfeited game can''t be reported'
);

SELECT * FROM finish();

ROLLBACK;
