-- Teams and rosters (LEAG-03). Run with `npm run db:test`.
BEGIN;

CREATE EXTENSION IF NOT EXISTS pgtap WITH SCHEMA extensions;

SELECT plan(17);

-- Oli runs a league and makes its teams. Mia signs up as a player, and Pat as a free agent.
INSERT INTO auth.users
  (id, email, raw_user_meta_data)
VALUES
  ('c0000000-0000-4000-8000-000000001101', 'oli@byui.edu', '{"full_name": "Oli Captain"}'),
  ('c0000000-0000-4000-8000-000000001102', 'mia@byui.edu', '{"full_name": "Mia Player"}'),
  ('c0000000-0000-4000-8000-000000001103', 'pat@byui.edu', '{"full_name": "Pat Spare"}');

UPDATE public.profiles
SET
  guidelines_version = 1,
  guidelines_accepted_at = now()
WHERE id BETWEEN 'c0000000-0000-4000-8000-000000001101' AND 'c0000000-0000-4000-8000-000000001103';

SET LOCAL ROLE authenticated;

SELECT set_config(
  'request.jwt.claims',
  '{"sub": "c0000000-0000-4000-8000-000000001101", "email": "oli@byui.edu"}',
  TRUE
);

SELECT isnt(
  public.create_league('Trivia Night', 'games', NULL, 'open'),
  NULL,
  'an organizer starts an open league'
);

SELECT lives_ok(
  $$select public.create_season(
    (select id from public.groups where slug like 'trivia-night%'),
    'Spring 2027', date '2027-03-01', date '2027-05-31', 'teams', 2, 4, 3, 1, 0, true, true
  )$$,
  'a season is started'
);

SELECT set_config(
  'request.jwt.claims',
  '{"sub": "c0000000-0000-4000-8000-000000001102", "email": "mia@byui.edu"}',
  TRUE
);

SELECT lives_ok(
  $$select public.join_season(
    (select id from public.league_seasons where name = 'Spring 2027'), 'player'
  )$$,
  'Mia signs up as a player'
);

SELECT set_config(
  'request.jwt.claims',
  '{"sub": "c0000000-0000-4000-8000-000000001103", "email": "pat@byui.edu"}',
  TRUE
);

SELECT lives_ok(
  $$select public.join_season(
    (select id from public.league_seasons where name = 'Spring 2027'), 'free_agent'
  )$$,
  'Pat signs up as a free agent'
);

SELECT set_config(
  'request.jwt.claims',
  '{"sub": "c0000000-0000-4000-8000-000000001101", "email": "oli@byui.edu"}',
  TRUE
);

SELECT lives_ok(
  $$select public.create_team(
    (select id from public.league_seasons where name = 'Spring 2027'), 'Reds', '#ff0000'
  )$$,
  'an organizer creates a team'
);

SELECT throws_ok(
  $$select public.create_team(
    (select id from public.league_seasons where name = 'Spring 2027'), ' Reds ', '#00ff00'
  )$$,
  '23505',
  'TEAM_NAME_TAKEN',
  'a season has one team of each name'
);

SELECT throws_ok(
  $$select public.create_team(
    (select id from public.league_seasons where name = 'Spring 2027'), 'Blues', 'blue'
  )$$,
  '22023',
  'INVALID_TEAM',
  'a team colour is a hex colour'
);

SELECT lives_ok(
  $$select public.create_team(
    (select id from public.league_seasons where name = 'Spring 2027'), 'Blues', '#0000ff'
  )$$,
  'an organizer creates a second team'
);

SELECT lives_ok(
  $$select public.assign_player(
    (select id from public.league_seasons where name = 'Spring 2027'),
    'c0000000-0000-4000-8000-000000001102',
    (select id from public.league_teams where name = 'Reds')
  )$$,
  'an organizer puts a player on a team'
);

SELECT throws_ok(
  $$select public.assign_player(
    (select id from public.league_seasons where name = 'Spring 2027'),
    'c0000000-0000-4000-8000-000000001103',
    (select id from public.league_teams where name = 'Reds')
  )$$,
  '22023',
  'NOT_A_PLAYER',
  'a free agent isn''t put on a team'
);

SELECT lives_ok(
  $$select public.update_team(
    (select id from public.league_teams where name = 'Reds'),
    'Reds', '#ff0000', 'c0000000-0000-4000-8000-000000001102'
  )$$,
  'a player on the team can be its captain'
);

SELECT results_eq(
  $$select captain_id from public.league_teams where name = 'Reds'$$,
  $$values ('c0000000-0000-4000-8000-000000001102'::uuid)$$,
  'the captain is saved'
);

-- Moving the captain to another team takes the captaincy away from the old one.
SELECT lives_ok(
  $$select public.assign_player(
    (select id from public.league_seasons where name = 'Spring 2027'),
    'c0000000-0000-4000-8000-000000001102',
    (select id from public.league_teams where name = 'Blues')
  )$$,
  'a captain moves to another team'
);

SELECT results_eq(
  $$select captain_id from public.league_teams where name = 'Reds'$$,
  $$values (NULL::uuid)$$,
  'the old team has no captain after a move'
);

SELECT throws_ok(
  $$select public.update_team(
    (select id from public.league_teams where name = 'Blues'),
    'Blues', '#0000ff', 'c0000000-0000-4000-8000-000000001103'
  )$$,
  '22023',
  'CAPTAIN_NOT_ON_TEAM',
  'a captain is on the team they captain'
);

-- Mia is a member who isn't an organizer, so she can't make teams, but she sees the rosters.
SELECT set_config(
  'request.jwt.claims',
  '{"sub": "c0000000-0000-4000-8000-000000001102", "email": "mia@byui.edu"}',
  TRUE
);

SELECT throws_ok(
  $$select public.create_team(
    (select id from public.league_seasons where name = 'Spring 2027'), 'Sneaky', '#123456'
  )$$,
  '42501',
  'NOT_LEAGUE_ORGANIZER',
  'a member who is not an organizer can''t make a team'
);

SELECT results_eq(
  $$select count(*) from public.league_registrations where team_id is not null$$,
  $$values (1::bigint)$$,
  'members see who is on each team'
);

ROLLBACK;
