-- Leagues and seasons (LEAG-01). Design document sections 8.9 and 9.13. A league is a group with
-- kind = 'league'. Its organizers run seasons: a name, dates, a format (teams or an individual
-- ladder), team sizes, points for a win, tie and loss, and whether registration is open. A league
-- has many seasons, but only one active season at a time.

-- A league is made like a group, then marked as one. Its creator is its owner, who can start
-- seasons. Leagues join the same way as groups, so join_policy is passed on.
CREATE FUNCTION public.create_league(
  name text,
  category_id text,
  description text DEFAULT NULL,
  join_policy text DEFAULT 'approval'
)
RETURNS text
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
declare
  league_slug text;
begin
  league_slug := public.create_group(
    create_league.name,
    create_league.category_id,
    create_league.description,
    create_league.join_policy
  );

  update public.groups as g
  set kind = 'league'
  where g.slug = league_slug and g.owner_id = auth.uid();

  return league_slug;
end;
$$;

REVOKE EXECUTE ON FUNCTION public.create_league(text, text, text, text) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.create_league(text, text, text, text) TO authenticated;

CREATE TABLE public.league_seasons (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  group_id uuid NOT NULL REFERENCES public.groups (id)
    ON DELETE CASCADE,
  name text NOT NULL CHECK (char_length(trim(name)) BETWEEN 3 AND 60),
  starts_on date NOT NULL,
  ends_on date NOT NULL,
  format text NOT NULL CHECK (format IN ('teams', 'ladder')),
  -- A ladder is for one person at a time, so its team sizes are 1.
  team_min INTEGER NOT NULL CHECK (team_min BETWEEN 1 AND 20),
  team_max INTEGER NOT NULL CHECK (team_max BETWEEN 1 AND 20),
  points_win INTEGER NOT NULL DEFAULT 3 CHECK (points_win BETWEEN 0 AND 10),
  points_tie INTEGER NOT NULL DEFAULT 1 CHECK (points_tie BETWEEN 0 AND 10),
  points_loss INTEGER NOT NULL DEFAULT 0 CHECK (points_loss BETWEEN 0 AND 10),
  registration_open BOOLEAN NOT NULL DEFAULT TRUE,
  active BOOLEAN NOT NULL DEFAULT TRUE,
  created_at timestamptz NOT NULL DEFAULT now(),
  CONSTRAINT season_ends_after_start CHECK (ends_on >= starts_on),
  CONSTRAINT season_team_sizes CHECK (team_min <= team_max),
  CONSTRAINT ladder_is_one_person CHECK (format != 'ladder' OR (team_min = 1 AND team_max = 1))
);

-- One active season per league.
CREATE UNIQUE INDEX league_seasons_one_active_idx ON public.league_seasons (group_id) WHERE active;

CREATE INDEX league_seasons_group_idx ON public.league_seasons (group_id, starts_on);

ALTER TABLE public.league_seasons ENABLE ROW LEVEL SECURITY;

-- Active members read the seasons of leagues that aren't hidden (and moderators, all). Writes go
-- through create_season().
CREATE POLICY "Members read seasons of visible leagues" ON public.league_seasons
FOR SELECT
TO authenticated
USING (
  private.is_moderator()
  OR (
    private.is_active_member()
    AND EXISTS (
      SELECT
      FROM public.groups AS g
      WHERE g.id = league_seasons.group_id AND g.hidden_at IS NULL
    )
  )
);

-- Starts a season in a league, for its owner or an organizer. Returns its id.
CREATE FUNCTION public.create_season(
  group_id uuid,
  name text,
  starts_on date,
  ends_on date,
  format text,
  team_min INTEGER,
  team_max INTEGER,
  points_win INTEGER,
  points_tie INTEGER,
  points_loss INTEGER,
  registration_open BOOLEAN,
  active BOOLEAN
)
RETURNS uuid
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
declare
  managed record := private.managed_group(create_season.group_id);
  season_id uuid;
begin
  if managed.role is null or managed.role not in ('owner', 'organizer') then
    raise exception 'NOT_LEAGUE_ORGANIZER' using errcode = '42501';
  end if;

  if (managed.g).kind <> 'league' then
    raise exception 'NOT_A_LEAGUE' using errcode = '22023';
  end if;

  if create_season.active and exists (
    select from public.league_seasons as s
    where s.group_id = (managed.g).id and s.active
  ) then
    raise exception 'SEASON_ALREADY_ACTIVE' using errcode = '22023';
  end if;

  insert into public.league_seasons (
    group_id, name, starts_on, ends_on, format, team_min, team_max,
    points_win, points_tie, points_loss, registration_open, active
  )
  values (
    (managed.g).id,
    trim(create_season.name),
    create_season.starts_on,
    create_season.ends_on,
    create_season.format,
    create_season.team_min,
    create_season.team_max,
    create_season.points_win,
    create_season.points_tie,
    create_season.points_loss,
    create_season.registration_open,
    create_season.active
  )
  returning id into season_id;

  return season_id;
end;
$$;

REVOKE EXECUTE
ON FUNCTION public.create_season(
  uuid,
  text,
  date,
  date,
  text,
  INTEGER,
  INTEGER,
  INTEGER,
  INTEGER,
  INTEGER,
  BOOLEAN,
  BOOLEAN
)
FROM PUBLIC, anon;
GRANT EXECUTE
ON FUNCTION public.create_season(
  uuid,
  text,
  date,
  date,
  text,
  INTEGER,
  INTEGER,
  INTEGER,
  INTEGER,
  INTEGER,
  BOOLEAN,
  BOOLEAN
)
TO authenticated;
