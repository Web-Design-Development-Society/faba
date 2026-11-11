-- Playoff brackets (LEAG-09). Run with `npm run db:test`.
BEGIN;

CREATE EXTENSION IF NOT EXISTS pgtap WITH SCHEMA extensions;

SELECT plan(11);

-- Oli runs a league with four teams. The regular season is finished, so the bracket can start.
INSERT INTO auth.users
  (id, email, raw_user_meta_data)
VALUES
  ('c0000000-0000-4000-8000-000000001701', 'oli@byui.edu', '{"full_name": "Oli Bracket"}');

UPDATE public.profiles
SET
  guidelines_version = 1,
  guidelines_accepted_at = now()
WHERE id = 'c0000000-0000-4000-8000-000000001701';

SET LOCAL ROLE authenticated;

SELECT set_config(
  'request.jwt.claims',
  '{"sub": "c0000000-0000-4000-8000-000000001701", "email": "oli@byui.edu"}',
  TRUE
);

SELECT isnt(
  public.create_league('Badminton Bracket', 'sports', NULL, 'open'),
  NULL,
  'a league starts'
);

SELECT lives_ok(
  $$select public.create_season(
    (select id from public.groups where slug like 'badminton-bracket%'),
    'Playoff Season', date '2099-06-01', date '2099-08-31', 'teams', 2, 4, 3, 1, 0, true, true
  )$$,
  'a season is started'
);

SELECT lives_ok(
  $$select
      public.create_team((select id from public.league_seasons where name = 'Playoff Season'), 'Ash', '#111111'),
      public.create_team((select id from public.league_seasons where name = 'Playoff Season'), 'Birch', '#222222'),
      public.create_team((select id from public.league_seasons where name = 'Playoff Season'), 'Cedar', '#333333'),
      public.create_team((select id from public.league_seasons where name = 'Playoff Season'), 'Dogwood', '#444444')$$,
  'four teams are made'
);

SELECT results_eq(
  $$select public.create_playoffs((select id from public.league_seasons where name = 'Playoff Season'),
    4, date '2099-07-01', time '18:00', 'Gym')$$,
  $$values (2)$$,
  'a bracket of four makes two first-round games'
);

SELECT throws_ok(
  $$select public.create_playoffs((select id from public.league_seasons where name = 'Playoff Season'),
    4, date '2099-07-01', time '18:00', 'Gym')$$,
  '22023',
  'PLAYOFFS_EXIST',
  'a season has one bracket'
);

SELECT throws_ok(
  $$select public.advance_playoffs((select id from public.league_seasons where name = 'Playoff Season'))$$,
  '22023',
  'ROUND_UNFINISHED',
  'the next round waits for this one'
);

SELECT lives_ok(
  $$select
      public.override_score((select id from public.league_games where stage = 'playoff' and bracket_round = 1 order by created_at limit 1), 5, 2, 'Result of the match'),
      public.override_score((select id from public.league_games where stage = 'playoff' and bracket_round = 1 order by created_at offset 1 limit 1), 1, 4, 'Result of the match')$$,
  'both first-round games are scored'
);

SELECT results_eq(
  $$select public.advance_playoffs((select id from public.league_seasons where name = 'Playoff Season'))$$,
  $$values (1)$$,
  'the winners play the final'
);

SELECT lives_ok(
  $$select public.override_score((select id from public.league_games where stage = 'playoff' and bracket_round = 2), 3, 1, 'The final')$$,
  'the final is scored'
);

SELECT results_eq(
  $$select public.advance_playoffs((select id from public.league_seasons where name = 'Playoff Season'))$$,
  $$values (0)$$,
  'after the final there is no next round'
);

SELECT results_eq(
  $$select count(*) from public.league_games where stage = 'playoff'$$,
  $$values (3::bigint)$$,
  'a four-team bracket is three games'
);

ROLLBACK;
