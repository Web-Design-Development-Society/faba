-- Registering for a season (LEAG-02). Run with `npm run db:test`.
BEGIN;

CREATE EXTENSION IF NOT EXISTS pgtap WITH SCHEMA extensions;

SELECT plan(14);

-- Oli runs a league with open joining. Mia is a member who signs up for its seasons.
INSERT INTO auth.users
  (id, email, raw_user_meta_data)
VALUES
  ('c0000000-0000-4000-8000-000000001001', 'oli@byui.edu', '{"full_name": "Oli Runner"}'),
  ('c0000000-0000-4000-8000-000000001002', 'mia@byui.edu', '{"full_name": "Mia Entrant"}');

UPDATE public.profiles
SET
  guidelines_version = 1,
  guidelines_accepted_at = now()
WHERE id BETWEEN 'c0000000-0000-4000-8000-000000001001' AND 'c0000000-0000-4000-8000-000000001002';

SET LOCAL ROLE authenticated;

SELECT set_config(
  'request.jwt.claims',
  '{"sub": "c0000000-0000-4000-8000-000000001001", "email": "oli@byui.edu"}',
  TRUE
);

SELECT isnt(
  public.create_league('Chess Ladder', 'games', NULL, 'open'),
  NULL,
  'an organizer starts an open league'
);

SELECT lives_ok(
  $$select public.create_season(
    (select id from public.groups where slug like 'chess-ladder%'),
    'Summer 2026', date '2026-06-01', date '2026-08-31', 'teams', 2, 4, 3, 1, 0, true, true
  )$$,
  'a season is open for registration'
);

-- Mia signs up as a player, with a note that's trimmed.
SELECT set_config(
  'request.jwt.claims',
  '{"sub": "c0000000-0000-4000-8000-000000001002", "email": "mia@byui.edu"}',
  TRUE
);

SELECT lives_ok(
  $$select public.join_season(
    (select id from public.league_seasons where name = 'Summer 2026'),
    'player',
    '  Keen to play  '
  )$$,
  'a member registers as a player'
);

SELECT results_eq(
  $$select kind, note from public.league_registrations
    where user_id = 'c0000000-0000-4000-8000-000000001002'$$,
  $$values ('player'::text, 'Keen to play'::text)$$,
  'the registration keeps its kind and a trimmed note'
);

SELECT results_eq(
  $$select status from public.group_members
    where user_id = 'c0000000-0000-4000-8000-000000001002'$$,
  $$values ('active'::text)$$,
  'registering joins the league group'
);

SELECT throws_ok(
  $$select public.join_season(
    (select id from public.league_seasons where name = 'Summer 2026'),
    'spectator'
  )$$,
  '22023',
  'INVALID_REGISTRATION',
  'only a player or a free agent can register'
);

SELECT lives_ok(
  $$select public.withdraw_from_season(
    (select id from public.league_seasons where name = 'Summer 2026')
  )$$,
  'a member withdraws before teams are set'
);

SELECT results_eq(
  $$select count(*) from public.league_registrations
    where user_id = 'c0000000-0000-4000-8000-000000001002'$$,
  $$values (0::bigint)$$,
  'withdrawing removes the registration'
);

SELECT lives_ok(
  $$select public.join_season(
    (select id from public.league_seasons where name = 'Summer 2026'),
    'free_agent'
  )$$,
  'a member can sign up again as a free agent'
);

-- Oli sets up a season that isn't taking registrations.
SELECT set_config(
  'request.jwt.claims',
  '{"sub": "c0000000-0000-4000-8000-000000001001", "email": "oli@byui.edu"}',
  TRUE
);

SELECT lives_ok(
  $$select public.create_season(
    (select id from public.groups where slug like 'chess-ladder%'),
    'Closed', date '2026-09-01', date '2026-11-30', 'teams', 2, 4, 3, 1, 0, false, false
  )$$,
  'a season can be closed to registration'
);

SELECT set_config(
  'request.jwt.claims',
  '{"sub": "c0000000-0000-4000-8000-000000001002", "email": "mia@byui.edu"}',
  TRUE
);

SELECT throws_ok(
  $$select public.join_season(
    (select id from public.league_seasons where name = 'Closed'),
    'player'
  )$$,
  '22023',
  'REGISTRATION_CLOSED',
  'a closed season takes no registrations'
);

-- Once the organizers set the teams, withdrawing and changing answers need the organizer.
RESET ROLE;

INSERT INTO public.league_teams (season_id, name, color)
VALUES
  ((SELECT id FROM public.league_seasons WHERE name = 'Summer 2026'), 'Reds', '#ff0000');

SET LOCAL ROLE authenticated;

SELECT throws_ok(
  $$select public.withdraw_from_season(
    (select id from public.league_seasons where name = 'Summer 2026')
  )$$,
  '22023',
  'TEAMS_SET',
  'withdrawing is closed once teams are set'
);

SELECT throws_ok(
  $$select public.join_season(
    (select id from public.league_seasons where name = 'Summer 2026'),
    'player'
  )$$,
  '22023',
  'TEAMS_SET',
  'changing a registration is closed once teams are set'
);

SELECT results_eq(
  $$select kind from public.league_registrations
    where user_id = 'c0000000-0000-4000-8000-000000001002'$$,
  $$values ('free_agent'::text)$$,
  'the registration stays as it was'
);

ROLLBACK;
