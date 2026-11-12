-- Requesting a substitute (LEAG-06). Run with `npm run db:test`.
BEGIN;

CREATE EXTENSION IF NOT EXISTS pgtap WITH SCHEMA extensions;

SELECT plan(21);

-- Oli runs a league. Mia and Pat captain the two teams, and Quinn is a free agent who can sub.
INSERT INTO auth.users
  (id, email, raw_user_meta_data)
VALUES
  ('c0000000-0000-4000-8000-000000001401', 'oli@byui.edu', '{"full_name": "Oli Organizer"}'),
  ('c0000000-0000-4000-8000-000000001402', 'mia@byui.edu', '{"full_name": "Mia Captain"}'),
  ('c0000000-0000-4000-8000-000000001403', 'pat@byui.edu', '{"full_name": "Pat Captain"}'),
  ('c0000000-0000-4000-8000-000000001404', 'quinn@byui.edu', '{"full_name": "Quinn Spare"}');

UPDATE public.profiles
SET
  guidelines_version = 1,
  guidelines_accepted_at = now()
WHERE id BETWEEN 'c0000000-0000-4000-8000-000000001401' AND 'c0000000-0000-4000-8000-000000001404';

SET LOCAL ROLE authenticated;

SELECT set_config(
  'request.jwt.claims',
  '{"sub": "c0000000-0000-4000-8000-000000001401", "email": "oli@byui.edu"}',
  TRUE
);

SELECT isnt(
  public.create_league('Kickball Club', 'sports', NULL, 'open'),
  NULL,
  'an organizer starts an open league'
);

-- The season is in the future, so its games haven't started.
SELECT lives_ok(
  $$select public.create_season(
    (select id from public.groups where slug like 'kickball-club%'),
    'Summer 2099', date '2099-06-01', date '2099-08-31', 'teams', 2, 4, 3, 1, 0, true, true
  )$$,
  'a season is started'
);

SELECT set_config(
  'request.jwt.claims',
  '{"sub": "c0000000-0000-4000-8000-000000001402", "email": "mia@byui.edu"}',
  TRUE
);

SELECT lives_ok(
  $$select public.join_season((select id from public.league_seasons where name = 'Summer 2099'), 'player')$$,
  'Mia signs up as a player'
);

SELECT set_config(
  'request.jwt.claims',
  '{"sub": "c0000000-0000-4000-8000-000000001403", "email": "pat@byui.edu"}',
  TRUE
);

SELECT lives_ok(
  $$select public.join_season((select id from public.league_seasons where name = 'Summer 2099'), 'player')$$,
  'Pat signs up as a player'
);

SELECT set_config(
  'request.jwt.claims',
  '{"sub": "c0000000-0000-4000-8000-000000001404", "email": "quinn@byui.edu"}',
  TRUE
);

SELECT lives_ok(
  $$select public.join_season((select id from public.league_seasons where name = 'Summer 2099'), 'free_agent')$$,
  'Quinn signs up as a free agent'
);

SELECT set_config(
  'request.jwt.claims',
  '{"sub": "c0000000-0000-4000-8000-000000001401", "email": "oli@byui.edu"}',
  TRUE
);

SELECT lives_ok(
  $$select public.create_team((select id from public.league_seasons where name = 'Summer 2099'), 'Reds', '#ff0000')$$,
  'a team is made'
);

SELECT lives_ok(
  $$select public.create_team((select id from public.league_seasons where name = 'Summer 2099'), 'Blues', '#0000ff')$$,
  'a second team is made'
);

SELECT lives_ok(
  $$select public.assign_player((select id from public.league_seasons where name = 'Summer 2099'),
    'c0000000-0000-4000-8000-000000001402', (select id from public.league_teams where name = 'Reds'))$$,
  'Mia is put on Reds'
);

SELECT lives_ok(
  $$select public.assign_player((select id from public.league_seasons where name = 'Summer 2099'),
    'c0000000-0000-4000-8000-000000001403', (select id from public.league_teams where name = 'Blues'))$$,
  'Pat is put on Blues'
);

SELECT lives_ok(
  $$select public.update_team((select id from public.league_teams where name = 'Reds'), 'Reds', '#ff0000',
    'c0000000-0000-4000-8000-000000001402')$$,
  'Mia captains Reds'
);

SELECT lives_ok(
  $$select public.update_team((select id from public.league_teams where name = 'Blues'), 'Blues', '#0000ff',
    'c0000000-0000-4000-8000-000000001403')$$,
  'Pat captains Blues'
);

SELECT lives_ok(
  $$select public.schedule_round_robin((select id from public.league_seasons where name = 'Summer 2099'),
    date '2099-06-02', 2, time '18:00', 'Field 1')$$,
  'the season has its game'
);

-- Only a captain asks for a sub.
SELECT throws_ok(
  $$select public.request_sub((select id from public.league_games where activity_id is not null))$$,
  '42501',
  'NOT_CAPTAIN',
  'an organizer who captains no team can''t ask for a sub'
);

SELECT set_config(
  'request.jwt.claims',
  '{"sub": "c0000000-0000-4000-8000-000000001402", "email": "mia@byui.edu"}',
  TRUE
);

SELECT lives_ok(
  $$select public.request_sub((select id from public.league_games where activity_id is not null))$$,
  'a captain asks the free agents for a sub'
);

-- A game takes one sub request an hour, from either captain.
SELECT set_config(
  'request.jwt.claims',
  '{"sub": "c0000000-0000-4000-8000-000000001403", "email": "pat@byui.edu"}',
  TRUE
);

SELECT throws_ok(
  $$select public.request_sub((select id from public.league_games where activity_id is not null))$$,
  '53400',
  'SUB_RATE_LIMITED',
  'a game takes one sub request an hour'
);

-- A player on a team can't take the sub spot, only a free agent can.
SELECT set_config(
  'request.jwt.claims',
  '{"sub": "c0000000-0000-4000-8000-000000001402", "email": "mia@byui.edu"}',
  TRUE
);

SELECT throws_ok(
  $$select public.accept_sub((select id from public.league_sub_requests limit 1))$$,
  '42501',
  'NOT_FREE_AGENT',
  'only a free agent can take a sub spot'
);

SELECT set_config(
  'request.jwt.claims',
  '{"sub": "c0000000-0000-4000-8000-000000001404", "email": "quinn@byui.edu"}',
  TRUE
);

SELECT lives_ok(
  $$select public.accept_sub((select id from public.league_sub_requests limit 1))$$,
  'the free agent accepts the sub spot'
);

SELECT throws_ok(
  $$select public.accept_sub((select id from public.league_sub_requests limit 1))$$,
  '22023',
  'SUB_FILLED',
  'the first to accept takes the spot'
);

SELECT results_eq(
  $$select count(*) from public.league_game_subs$$,
  $$values (1::bigint)$$,
  'the sub is added to that game'
);

SELECT results_eq(
  $$select count(*) from public.league_sub_requests where filled_by is not null$$,
  $$values (1::bigint)$$,
  'the request records who filled it'
);

RESET ROLE;

SELECT results_eq(
  $$select count(*) from public.notifications where type = 'sub_needed'$$,
  $$values (1::bigint)$$,
  'only the free agents hear about the sub request'
);

SELECT * FROM finish();

ROLLBACK;
