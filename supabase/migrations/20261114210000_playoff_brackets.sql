-- Playoff brackets (LEAG-09). At the end of a season, the organizer seeds a bracket from the final
-- standings: the top 2, 4 or 8 teams, paired 1 against last, 2 against second to last, and so on.
-- Each bracket game is an activity, like a regular game (LEAG-04), and is scored the same way
-- (LEAG-05). When a round is finished, the organizer starts the next, with the winners paired in
-- order. A round with one game is the final, and its winner is the champion.

ALTER TABLE public.league_games
ADD COLUMN stage text NOT NULL DEFAULT 'regular' CHECK (stage IN ('regular', 'playoff')),
-- For playoff games, the round of the bracket: 1 is the first round.
ADD COLUMN bracket_round INTEGER CHECK (bracket_round >= 1),
ADD CONSTRAINT playoff_has_round CHECK ((stage = 'playoff') = (bracket_round IS NOT NULL));

-- Starts a bracket from the season's standings. Regular games must be finished first. Returns how
-- many games the first round has.
CREATE FUNCTION public.create_playoffs(
  season_id uuid,
  size INTEGER,
  first_day date,
  starts_time TIME,
  place text
)
RETURNS INTEGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
declare
  s public.league_seasons := private.managed_season(create_playoffs.season_id);
  clean_place text := trim(create_playoffs.place);
  seeds uuid[];
  n INTEGER;
  i INTEGER;
  home uuid;
  away uuid;
  home_name text;
  away_name text;
  activity_id uuid;
begin
  if size is null or size not in (2, 4, 8) then
    raise exception 'INVALID_BRACKET_SIZE' using errcode = '22023';
  end if;

  if char_length(clean_place) not between 1 and 120 then
    raise exception 'INVALID_PLACE' using errcode = '22023';
  end if;

  if exists (select from public.league_games as g where g.season_id = s.id and g.stage = 'playoff') then
    raise exception 'PLAYOFFS_EXIST' using errcode = '22023';
  end if;

  if exists (
    select from public.league_games as g
    where g.season_id = s.id and g.stage = 'regular'
      and g.away_team_id is not null and g.status in ('scheduled', 'reported')
  ) then
    raise exception 'REGULAR_UNFINISHED' using errcode = '22023';
  end if;

  select array_agg(st.team_id order by row_number)
  into seeds
  from (
    select ss.team_id, row_number() over () as row_number
    from public.season_standings(create_playoffs.season_id) as ss
    limit size
  ) as st;

  n := coalesce(array_length(seeds, 1), 0);
  if n < size then
    raise exception 'NOT_ENOUGH_FOR_BRACKET' using errcode = '22023';
  end if;

  -- Seed 1 plays the last seed, 2 plays the second to last, and so on.
  for i in 1..(n / 2) loop
    home := seeds[i];
    away := seeds[n + 1 - i];

    select t.name into home_name from public.league_teams as t where t.id = home;
    select t.name into away_name from public.league_teams as t where t.id = away;

    insert into public.activities (organizer_id, category_id, title, starts_at, timezone, location_name, group_id, visibility)
    values (
      auth.uid(),
      (select g.category_id from public.groups as g where g.id = s.group_id),
      left('Playoffs: ' || home_name || ' vs ' || away_name, 80),
      ((create_playoffs.first_day)::timestamp + create_playoffs.starts_time) AT TIME ZONE 'America/Boise',
      'America/Boise',
      clean_place,
      s.group_id,
      'group'
    )
    returning id into activity_id;

    insert into public.league_games (season_id, round, home_team_id, away_team_id, activity_id, stage, bracket_round)
    values (s.id, 100 + 1, home, away, activity_id, 'playoff', 1);
  end loop;

  return n / 2;
end;
$$;

REVOKE EXECUTE
ON FUNCTION public.create_playoffs(uuid, INTEGER, date, TIME, text)
FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.create_playoffs(uuid, INTEGER, date, TIME, text) TO authenticated;

-- Starts the next round once the last one is finished. The winners are paired in the order their
-- games were played. Returns how many games the new round has, or 0 when the last round was the
-- final.
CREATE FUNCTION public.advance_playoffs(season_id uuid)
RETURNS INTEGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
declare
  s public.league_seasons := private.managed_season(advance_playoffs.season_id);
  last_round INTEGER;
  last_games INTEGER;
  winners uuid[];
  i INTEGER;
  home uuid;
  away uuid;
  home_name text;
  away_name text;
  template public.league_games;
  starts timestamptz;
  activity_id uuid;
  made INTEGER := 0;
begin
  select max(g.bracket_round), count(*)::INTEGER
  into last_round, last_games
  from public.league_games as g
  where g.season_id = s.id and g.stage = 'playoff' and g.bracket_round = (
    select max(x.bracket_round) from public.league_games as x
    where x.season_id = s.id and x.stage = 'playoff'
  );

  if last_round is null then
    raise exception 'NO_PLAYOFFS' using errcode = '22023';
  end if;

  if exists (
    select from public.league_games as g
    where g.season_id = s.id and g.stage = 'playoff' and g.bracket_round = last_round
      and g.status not in ('confirmed', 'forfeit')
  ) then
    raise exception 'ROUND_UNFINISHED' using errcode = '22023';
  end if;

  -- A round of one game is the final, so once it's finished there's no next round.
  if last_games = 1 then
    return 0;
  end if;

  -- The winner of each game: the higher score, or the team that didn't forfeit.
  select array_agg(
    case
      when g.status = 'forfeit' then (case when g.forfeit_team_id = g.home_team_id then g.away_team_id else g.home_team_id end)
      when g.home_score > g.away_score then g.home_team_id
      else g.away_team_id
    end
    order by a.starts_at, g.created_at
  )
  into winners
  from public.league_games as g
  join public.activities as a on a.id = g.activity_id
  where g.season_id = s.id and g.stage = 'playoff' and g.bracket_round = last_round;

  if exists (
    select from public.league_games as g
    where g.season_id = s.id and g.stage = 'playoff' and g.bracket_round = last_round
      and g.status = 'confirmed' and g.home_score = g.away_score
  ) then
    raise exception 'PLAYOFF_TIE' using errcode = '22023';
  end if;

  select * into template
  from public.league_games as g
  where g.season_id = s.id and g.stage = 'playoff' and g.bracket_round = last_round
  order by g.created_at
  limit 1;

  select a.starts_at into starts from public.activities as a where a.id = template.activity_id;

  for i in 1..(array_length(winners, 1) / 2) loop
    home := winners[2 * i - 1];
    away := winners[2 * i];

    select t.name into home_name from public.league_teams as t where t.id = home;
    select t.name into away_name from public.league_teams as t where t.id = away;

    insert into public.activities (organizer_id, category_id, title, starts_at, timezone, location_name, group_id, visibility)
    values (
      auth.uid(),
      (select g.category_id from public.groups as g where g.id = s.group_id),
      left('Playoffs: ' || home_name || ' vs ' || away_name, 80),
      starts + interval '7 days',
      'America/Boise',
      (select a.location_name from public.activities as a where a.id = template.activity_id),
      s.group_id,
      'group'
    )
    returning id into activity_id;

    insert into public.league_games (season_id, round, home_team_id, away_team_id, activity_id, stage, bracket_round)
    values (s.id, 100 + last_round + 1, home, away, activity_id, 'playoff', last_round + 1);

    made := made + 1;
  end loop;

  return made;
end;
$$;

REVOKE EXECUTE ON FUNCTION public.advance_playoffs(uuid) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.advance_playoffs(uuid) TO authenticated;
