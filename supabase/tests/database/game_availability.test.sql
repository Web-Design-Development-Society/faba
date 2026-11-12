-- Game availability (LEAG-07). Run with `npm run db:test`.
BEGIN;

CREATE EXTENSION IF NOT EXISTS pgtap WITH SCHEMA extensions;

SELECT plan(14);

-- Oli runs a league with two teams. Mia and Pat play, and Quinn is a free agent who isn't on a team.
INSERT INTO auth.users
  (id, email, raw_user_meta_data)
VALUES
  ('c0000000-0000-4000-8000-000000001501', 'oli@byui.edu', '{"full_name": "Oli Avail"}'),
  ('c0000000-0000-4000-8000-000000001502', 'mia@byui.edu', '{"full_name": "Mia Avail"}'),
  ('c0000000-0000-4000-8000-000000001503', 'pat@byui.edu', '{"full_name": "Pat Avail"}'),
  ('c0000000-0000-4000-8000-000000001504', 'quinn@byui.edu', '{"full_name": "Quinn Avail"}');

UPDATE public.profiles
SET
  guidelines_version = 1,
  guidelines_accepted_at = now()
WHERE id BETWEEN 'c0000000-0000-4000-8000-000000001501' AND 'c0000000-0000-4000-8000-000000001504';

SET LOCAL ROLE authenticated;

SELECT set_config(
  'request.jwt.claims',
  '{"sub": "c0000000-0000-4000-8000-000000001501", "email": "oli@byui.edu"}',
  TRUE
);

SELECT isnt(public.create_league('Bowling Night', 'games', NULL, 'open'), NULL, 'a league starts');

SELECT lives_ok(
  $$select public.create_season(
    (select id from public.groups where slug like 'bowling-night%'),
    'Summer 2099', date '2099-06-01', date '2099-08-31', 'teams', 2, 4, 3, 1, 0, true, true
  )$$,
  'a season is started'
);

SELECT set_config(
  'request.jwt.claims',
  '{"sub": "c0000000-0000-4000-8000-000000001502", "email": "mia@byui.edu"}',
  TRUE
);

SELECT lives_ok(
  $$select public.join_season((select id from public.league_seasons where name = 'Summer 2099'), 'player')$$,
  'Mia plays'
);

SELECT set_config(
  'request.jwt.claims',
  '{"sub": "c0000000-0000-4000-8000-000000001503", "email": "pat@byui.edu"}',
  TRUE
);

SELECT lives_ok(
  $$select public.join_season((select id from public.league_seasons where name = 'Summer 2099'), 'player')$$,
  'Pat plays'
);

SELECT set_config(
  'request.jwt.claims',
  '{"sub": "c0000000-0000-4000-8000-000000001504", "email": "quinn@byui.edu"}',
  TRUE
);

SELECT lives_ok(
  $$select public.join_season((select id from public.league_seasons where name = 'Summer 2099'), 'free_agent')$$,
  'Quinn is a free agent'
);

SELECT set_config(
  'request.jwt.claims',
  '{"sub": "c0000000-0000-4000-8000-000000001501", "email": "oli@byui.edu"}',
  TRUE
);

SELECT lives_ok(
  $$select public.create_team((select id from public.league_seasons where name = 'Summer 2099'), 'Reds', '#ff0000')$$,
  'Reds is made'
);

SELECT lives_ok(
  $$select public.create_team((select id from public.league_seasons where name = 'Summer 2099'), 'Blues', '#0000ff')$$,
  'Blues is made'
);

SELECT lives_ok(
  $$select public.assign_player((select id from public.league_seasons where name = 'Summer 2099'),
    'c0000000-0000-4000-8000-000000001502', (select id from public.league_teams where name = 'Reds'))$$,
  'Mia is on Reds'
);

SELECT lives_ok(
  $$select public.assign_player((select id from public.league_seasons where name = 'Summer 2099'),
    'c0000000-0000-4000-8000-000000001503', (select id from public.league_teams where name = 'Blues'))$$,
  'Pat is on Blues'
);

SELECT lives_ok(
  $$select public.schedule_round_robin((select id from public.league_seasons where name = 'Summer 2099'),
    date '2099-06-02', 2, time '18:00', 'Lanes')$$,
  'two teams make one game'
);

SELECT set_config(
  'request.jwt.claims',
  '{"sub": "c0000000-0000-4000-8000-000000001502", "email": "mia@byui.edu"}',
  TRUE
);

SELECT lives_ok(
  $$select public.set_game_availability((select id from public.league_games where activity_id is not null), true)$$,
  'Mia can play, and is going'
);

SELECT results_eq(
  $$select r.status from public.rsvps r
    join public.league_games g on g.activity_id = r.activity_id
    where r.user_id = 'c0000000-0000-4000-8000-000000001502'$$,
  $$values ('going'::text)$$,
  'the answer is the RSVP, so the game is in Plans'
);

SELECT lives_ok(
  $$select public.set_game_availability((select id from public.league_games where activity_id is not null), false)$$,
  'Mia can''t play after all'
);

SELECT set_config(
  'request.jwt.claims',
  '{"sub": "c0000000-0000-4000-8000-000000001504", "email": "quinn@byui.edu"}',
  TRUE
);

SELECT throws_ok(
  $$select public.set_game_availability((select id from public.league_games where activity_id is not null), true)$$,
  '42501',
  'NOT_PLAYING_IN_GAME',
  'a free agent who isn''t on a team can''t answer for the game'
);

ROLLBACK;
