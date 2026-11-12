-- The individual ladder (LEAG-08). Run with `npm run db:test`.
BEGIN;

CREATE EXTENSION IF NOT EXISTS pgtap WITH SCHEMA extensions;

SELECT plan(9);

-- Oli runs a ladder. Mia and Pat sign up as players, and Quinn is a member who doesn't play.
INSERT INTO auth.users
  (id, email, raw_user_meta_data)
VALUES
  ('c0000000-0000-4000-8000-000000001601', 'oli@byui.edu', '{"full_name": "Oli Ladder"}'),
  ('c0000000-0000-4000-8000-000000001602', 'mia@byui.edu', '{"full_name": "Mia Ladder"}'),
  ('c0000000-0000-4000-8000-000000001603', 'pat@byui.edu', '{"full_name": "Pat Ladder"}'),
  ('c0000000-0000-4000-8000-000000001604', 'quinn@byui.edu', '{"full_name": "Quinn Ladder"}');

UPDATE public.profiles
SET
  guidelines_version = 1,
  guidelines_accepted_at = now()
WHERE id BETWEEN 'c0000000-0000-4000-8000-000000001601' AND 'c0000000-0000-4000-8000-000000001604';

SET LOCAL ROLE authenticated;

SELECT set_config(
  'request.jwt.claims',
  '{"sub": "c0000000-0000-4000-8000-000000001601", "email": "oli@byui.edu"}',
  TRUE
);

SELECT isnt(
  public.create_league('Ping Pong Ladder', 'games', NULL, 'open'),
  NULL,
  'a league starts'
);

SELECT lives_ok(
  $$select public.create_season(
    (select id from public.groups where slug like 'ping-pong-ladder%'),
    'Ladder 2099', date '2099-06-01', date '2099-08-31', 'ladder', 1, 1, 3, 1, 0, true, true
  )$$,
  'a ladder season is started'
);

SELECT set_config(
  'request.jwt.claims',
  '{"sub": "c0000000-0000-4000-8000-000000001602", "email": "mia@byui.edu"}',
  TRUE
);

SELECT lives_ok(
  $$select public.join_season((select id from public.league_seasons where name = 'Ladder 2099'), 'player')$$,
  'Mia signs up'
);

SELECT set_config(
  'request.jwt.claims',
  '{"sub": "c0000000-0000-4000-8000-000000001603", "email": "pat@byui.edu"}',
  TRUE
);

SELECT lives_ok(
  $$select public.join_season((select id from public.league_seasons where name = 'Ladder 2099'), 'player')$$,
  'Pat signs up'
);

SELECT set_config(
  'request.jwt.claims',
  '{"sub": "c0000000-0000-4000-8000-000000001601", "email": "oli@byui.edu"}',
  TRUE
);

SELECT results_eq(
  $$select public.enter_ladder((select id from public.league_seasons where name = 'Ladder 2099'))$$,
  $$values (2)$$,
  'each player becomes a team of one'
);

SELECT results_eq(
  $$select count(*) from public.league_teams t
    join public.league_seasons s on s.id = t.season_id
    where s.name = 'Ladder 2099' and t.captain_id is not null$$,
  $$values (2::bigint)$$,
  'each one-person team is captained by its player'
);

SELECT lives_ok(
  $$select public.schedule_round_robin((select id from public.league_seasons where name = 'Ladder 2099'),
    date '2099-06-02', 2, time '18:00', 'Table 1')$$,
  'the ladder schedules games between two players'
);

SELECT results_eq(
  $$select count(*) from public.league_games where activity_id is not null$$,
  $$values (1::bigint)$$,
  'a game is between two players'
);

SELECT results_eq(
  $$select public.enter_ladder((select id from public.league_seasons where name = 'Ladder 2099'))$$,
  $$values (0)$$,
  'entering again makes no new teams'
);

ROLLBACK;
