-- Teams and rosters (LEAG-03). An organizer creates a season's teams, with a name, a colour and a
-- captain, and assigns or moves the players who signed up as players (LEAG-02). The roster is
-- visible to the league's members. Auto-balance is a later, optional step.

ALTER TABLE public.league_registrations
ADD COLUMN team_id uuid REFERENCES public.league_teams (id)
  ON DELETE SET NULL;

CREATE INDEX league_registrations_team_idx ON public.league_registrations (team_id);

-- The season and league that a team's or registration's organizers can manage, if the caller is an
-- owner or organizer of its league.
CREATE FUNCTION private.managed_season(season_id uuid)
RETURNS public.league_seasons
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
declare
  s public.league_seasons;
  managed record;
begin
  select * into s
  from public.league_seasons as x
  where x.id = managed_season.season_id;

  if not found then
    raise exception 'SEASON_NOT_FOUND' using errcode = 'P0002';
  end if;

  managed := private.managed_group(s.group_id);

  if managed.role is null or managed.role not in ('owner', 'organizer') then
    raise exception 'NOT_LEAGUE_ORGANIZER' using errcode = '42501';
  end if;

  if (managed.g).kind <> 'league' then
    raise exception 'NOT_A_LEAGUE' using errcode = '22023';
  end if;

  return s;
end;
$$;

REVOKE EXECUTE ON FUNCTION private.managed_season(uuid) FROM PUBLIC, anon, authenticated;

-- Creates a team in a season. Its captain and its players come after.
CREATE FUNCTION public.create_team(season_id uuid, name text, color text)
RETURNS uuid
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
declare
  s public.league_seasons := private.managed_season(create_team.season_id);
  team_id uuid;
begin
  if char_length(trim(create_team.name)) not between 1 and 40 then
    raise exception 'INVALID_TEAM' using errcode = '22023';
  end if;

  if create_team.color is null or create_team.color !~ '^#[0-9a-fA-F]{6}$' then
    raise exception 'INVALID_TEAM' using errcode = '22023';
  end if;

  insert into public.league_teams (season_id, name, color)
  values (s.id, trim(create_team.name), create_team.color)
  returning id into team_id;

  return team_id;
exception
  when unique_violation then
    raise exception 'TEAM_NAME_TAKEN' using errcode = '23505';
end;
$$;

REVOKE EXECUTE ON FUNCTION public.create_team(uuid, text, text) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.create_team(uuid, text, text) TO authenticated;

-- Renames a team, changes its colour, or names its captain. A captain is a player on the team.
CREATE FUNCTION public.update_team(
  team_id uuid,
  name text,
  color text,
  captain_id uuid DEFAULT NULL
)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
declare
  t public.league_teams;
begin
  select * into t
  from public.league_teams as x
  where x.id = update_team.team_id;

  if not found then
    raise exception 'TEAM_NOT_FOUND' using errcode = 'P0002';
  end if;

  perform private.managed_season(t.season_id);

  if char_length(trim(update_team.name)) not between 1 and 40
    or update_team.color is null
    or update_team.color !~ '^#[0-9a-fA-F]{6}$' then
    raise exception 'INVALID_TEAM' using errcode = '22023';
  end if;

  if update_team.captain_id is not null and not exists (
    select from public.league_registrations as r
    where r.season_id = t.season_id
      and r.user_id = update_team.captain_id
      and r.team_id = t.id
      and r.kind = 'player'
  ) then
    raise exception 'CAPTAIN_NOT_ON_TEAM' using errcode = '22023';
  end if;

  update public.league_teams as x
  set
    name = trim(update_team.name),
    color = update_team.color,
    captain_id = update_team.captain_id
  where x.id = t.id;
exception
  when unique_violation then
    raise exception 'TEAM_NAME_TAKEN' using errcode = '23505';
end;
$$;

REVOKE EXECUTE ON FUNCTION public.update_team(uuid, text, text, uuid) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.update_team(uuid, text, text, uuid) TO authenticated;

-- Puts a player on a team, moves them to another, or takes them off (team_id null). Only players
-- who signed up as players can be on a team. A player who leaves a team as its captain stops being
-- its captain.
CREATE FUNCTION public.assign_player(season_id uuid, user_id uuid, team_id uuid DEFAULT NULL)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
declare
  s public.league_seasons := private.managed_season(assign_player.season_id);
  r public.league_registrations;
begin
  select * into r
  from public.league_registrations as x
  where x.season_id = s.id and x.user_id = assign_player.user_id;

  if not found then
    raise exception 'REGISTRATION_NOT_FOUND' using errcode = 'P0002';
  end if;

  if assign_player.team_id is not null and r.kind <> 'player' then
    raise exception 'NOT_A_PLAYER' using errcode = '22023';
  end if;

  if assign_player.team_id is not null and not exists (
    select from public.league_teams as t
    where t.id = assign_player.team_id and t.season_id = s.id
  ) then
    raise exception 'TEAM_NOT_FOUND' using errcode = 'P0002';
  end if;

  if r.team_id is not null and r.team_id is distinct from assign_player.team_id then
    update public.league_teams as t
    set captain_id = null
    where t.id = r.team_id and t.captain_id = assign_player.user_id;
  end if;

  update public.league_registrations as x
  set team_id = assign_player.team_id
  where x.season_id = s.id and x.user_id = assign_player.user_id;
end;
$$;

REVOKE EXECUTE ON FUNCTION public.assign_player(uuid, uuid, uuid) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.assign_player(uuid, uuid, uuid) TO authenticated;
