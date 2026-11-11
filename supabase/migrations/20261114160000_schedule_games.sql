-- Scheduling games (LEAG-04). An organizer makes a single round robin for a season: every team
-- plays every other once, one round a week. Each game is an activity in the league's group, so
-- RSVPs, reminders and notifications work as they do for any activity. A team that sits out a round
-- (an odd number of teams) has a bye, which is a row with no game. Recurring patterns (REC) aren't
-- used, because each game is one activity.

CREATE TABLE public.league_games (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  season_id uuid NOT NULL REFERENCES public.league_seasons (id)
    ON DELETE CASCADE,
  round INTEGER NOT NULL CHECK (round >= 1),
  home_team_id uuid NOT NULL REFERENCES public.league_teams (id)
    ON DELETE CASCADE,
  -- Empty for a bye.
  away_team_id uuid REFERENCES public.league_teams (id)
    ON DELETE CASCADE,
  activity_id uuid UNIQUE REFERENCES public.activities (id)
    ON DELETE CASCADE,
  created_at timestamptz NOT NULL DEFAULT now(),
  CONSTRAINT game_teams_differ CHECK (away_team_id IS NULL OR away_team_id != home_team_id),
  -- A game has an activity; a bye has neither a second team nor an activity.
  CONSTRAINT game_has_activity CHECK ((away_team_id IS NULL) = (activity_id IS NULL))
);

CREATE INDEX league_games_season_round_idx ON public.league_games (season_id, round);

ALTER TABLE public.league_games ENABLE ROW LEVEL SECURITY;

CREATE POLICY "Members read games of visible leagues" ON public.league_games
FOR SELECT
TO authenticated
USING (private.can_see_season(league_games.season_id));

-- Makes the season's round robin. Teams play once each, one round a week, from `first_day` on the
-- weekday given (1 for Monday to 7 for Sunday) at `starts_time`, at `place`. A season is scheduled
-- once. Returns how many games were made.
CREATE FUNCTION public.schedule_round_robin(
  season_id uuid,
  first_day date,
  weekday INTEGER,
  starts_time TIME,
  place text
)
RETURNS INTEGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
declare
  s public.league_seasons := private.managed_season(schedule_round_robin.season_id);
  teams uuid[];
  slots uuid[];
  n INTEGER;
  round_no INTEGER;
  i INTEGER;
  a uuid;
  b uuid;
  home uuid;
  away uuid;
  day date;
  made INTEGER := 0;
  home_name text;
  away_name text;
  clean_place text := trim(schedule_round_robin.place);
  activity_id uuid;
begin
  if char_length(clean_place) not between 1 and 120 then
    raise exception 'INVALID_PLACE' using errcode = '22023';
  end if;

  if weekday is null or weekday not between 1 and 7 then
    raise exception 'INVALID_WEEKDAY' using errcode = '22023';
  end if;

  if exists (select from public.league_games as g where g.season_id = s.id) then
    raise exception 'SCHEDULE_EXISTS' using errcode = '22023';
  end if;

  select array_agg(t.id order by t.created_at, t.name)
  into teams
  from public.league_teams as t
  where t.season_id = s.id;

  n := coalesce(array_length(teams, 1), 0);
  if n < 2 then
    raise exception 'NOT_ENOUGH_TEAMS' using errcode = '22023';
  end if;

  -- The circle method: with an odd count, a placeholder (null) stands in for the bye.
  slots := teams;
  if n % 2 = 1 then
    slots := slots || array[null::uuid];
  end if;
  n := array_length(slots, 1);

  -- The first game falls on the first `weekday` on or after first_day.
  day := first_day + ((weekday - extract(isodow from first_day)::INTEGER + 7) % 7);

  for round_no in 1..(n - 1) loop
    if day + ((round_no - 1) * 7) > s.ends_on then
      raise exception 'SCHEDULE_PAST_SEASON' using errcode = '22023';
    end if;

    for i in 0..(n / 2 - 1) loop
      a := slots[i + 1];
      b := slots[n - i];

      if a is null or b is null then
        -- The team that sits this round out has a bye.
        insert into public.league_games (season_id, round, home_team_id, away_team_id, activity_id)
        values (s.id, round_no, coalesce(a, b), null, null);
        continue;
      end if;

      -- Swap home and away from round to round, so no team always plays at home.
      if (round_no + i) % 2 = 0 then
        home := a;
        away := b;
      else
        home := b;
        away := a;
      end if;

      select t.name into home_name from public.league_teams as t where t.id = home;
      select t.name into away_name from public.league_teams as t where t.id = away;

      insert into public.activities (
        organizer_id,
        category_id,
        title,
        starts_at,
        timezone,
        location_name,
        group_id,
        visibility
      )
      values (
        auth.uid(),
        (select g.category_id from public.groups as g where g.id = s.group_id),
        left(home_name || ' vs ' || away_name, 80),
        ((day + ((round_no - 1) * 7))::timestamp + schedule_round_robin.starts_time)
          AT TIME ZONE 'America/Boise',
        'America/Boise',
        clean_place,
        s.group_id,
        'group'
      )
      returning id into activity_id;

      insert into public.league_games (season_id, round, home_team_id, away_team_id, activity_id)
      values (s.id, round_no, home, away, activity_id);

      made := made + 1;
    end loop;

    -- Keep the first team in place and rotate the rest.
    slots := array[slots[1]] || array[slots[n]] || slots[2:n - 1];
  end loop;

  return made;
end;
$$;

REVOKE EXECUTE
ON FUNCTION public.schedule_round_robin(uuid, date, INTEGER, TIME, text)
FROM PUBLIC, anon;
GRANT EXECUTE
ON FUNCTION public.schedule_round_robin(uuid, date, INTEGER, TIME, text)
TO authenticated;

-- Changes one game's day, time or place. The game's activity changes with it.
CREATE FUNCTION public.update_game(game_id uuid, day date, starts_time TIME, place text)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
declare
  game public.league_games;
  clean_place text := trim(update_game.place);
begin
  select * into game
  from public.league_games as g
  where g.id = update_game.game_id;

  if not found then
    raise exception 'GAME_NOT_FOUND' using errcode = 'P0002';
  end if;

  perform private.managed_season(game.season_id);

  if game.activity_id is null then
    raise exception 'NOT_A_GAME' using errcode = '22023';
  end if;

  if char_length(clean_place) not between 1 and 120 then
    raise exception 'INVALID_PLACE' using errcode = '22023';
  end if;

  update public.activities as a
  set
    starts_at = ((update_game.day::timestamp + update_game.starts_time) AT TIME ZONE 'America/Boise'),
    location_name = clean_place
  where a.id = game.activity_id;
end;
$$;

REVOKE EXECUTE ON FUNCTION public.update_game(uuid, date, TIME, text) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.update_game(uuid, date, TIME, text) TO authenticated;
