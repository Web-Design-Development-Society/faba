-- Scores and standings (LEAG-05). A captain reports a game's score. The other team's captain, or an
-- organizer, confirms it. Standings count confirmed results only. A forfeit is a status: the team
-- that forfeits takes a loss, and the other team a win. An organizer can override a score, and the
-- override is audit-logged.

ALTER TABLE public.league_games
ADD COLUMN home_score INTEGER CHECK (home_score BETWEEN 0 AND 999),
ADD COLUMN away_score INTEGER CHECK (away_score BETWEEN 0 AND 999),
ADD COLUMN status text NOT NULL DEFAULT 'scheduled' CHECK (
  status IN ('scheduled', 'reported', 'confirmed', 'forfeit')
),
-- The team whose captain reported the score, who can't confirm it.
ADD COLUMN reporting_team_id uuid REFERENCES public.league_teams (id)
  ON DELETE SET NULL,
ADD COLUMN reported_by uuid REFERENCES public.profiles (id)
  ON DELETE SET NULL,
ADD COLUMN confirmed_by uuid REFERENCES public.profiles (id)
  ON DELETE SET NULL,
ADD COLUMN forfeit_team_id uuid REFERENCES public.league_teams (id)
  ON DELETE SET NULL,
ADD CONSTRAINT game_score_matches_status
  CHECK (
    (status IN ('reported', 'confirmed')) = (home_score IS NOT NULL AND away_score IS NOT NULL)
  ),
ADD CONSTRAINT game_forfeit_has_team CHECK ((status = 'forfeit') = (forfeit_team_id IS NOT NULL)),
ADD CONSTRAINT bye_has_no_result
  CHECK (
    away_team_id IS NOT NULL
    OR (status = 'scheduled' AND home_score IS NULL AND away_score IS NULL)
  );

-- Who runs the game's score: the captains of its two teams, and the league's organizers.
CREATE FUNCTION private.captain_team(game_id uuid)
RETURNS uuid
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = ''
AS $$
  SELECT t.id
  FROM public.league_games AS g
  JOIN public.league_teams AS t ON (t.id = g.home_team_id OR t.id = g.away_team_id)
  WHERE g.id = captain_team.game_id AND t.captain_id = auth.uid()
  LIMIT 1;
$$;

REVOKE EXECUTE ON FUNCTION private.captain_team(uuid) FROM PUBLIC, anon, authenticated;

-- A captain reports the score of a game. Their team is the one that reported it, so the other
-- team's captain has to confirm it. Reporting again replaces the score and asks for a confirmation.
CREATE FUNCTION public.report_score(game_id uuid, home_score INTEGER, away_score INTEGER)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
declare
  game public.league_games;
  mine uuid := private.captain_team(report_score.game_id);
begin
  select * into game
  from public.league_games as g
  where g.id = report_score.game_id
  for update;

  if not found then
    raise exception 'GAME_NOT_FOUND' using errcode = 'P0002';
  end if;

  if game.away_team_id is null then
    raise exception 'NOT_A_GAME' using errcode = '22023';
  end if;

  if game.status in ('confirmed', 'forfeit') then
    raise exception 'GAME_LOCKED' using errcode = '22023';
  end if;

  if mine is null then
    raise exception 'NOT_CAPTAIN' using errcode = '42501';
  end if;

  if report_score.home_score is null or report_score.away_score is null
    or report_score.home_score < 0 or report_score.away_score < 0
    or report_score.home_score > 999 or report_score.away_score > 999 then
    raise exception 'INVALID_SCORE' using errcode = '22023';
  end if;

  update public.league_games as g
  set
    home_score = report_score.home_score,
    away_score = report_score.away_score,
    status = 'reported',
    reporting_team_id = mine,
    reported_by = auth.uid(),
    confirmed_by = null
  where g.id = game.id;
end;
$$;

REVOKE EXECUTE ON FUNCTION public.report_score(uuid, INTEGER, INTEGER) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.report_score(uuid, INTEGER, INTEGER) TO authenticated;

-- The other team's captain, or an organizer, confirms a reported score.
CREATE FUNCTION public.confirm_score(game_id uuid)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
declare
  game public.league_games;
  organizer boolean;
  opposing boolean;
begin
  select * into game
  from public.league_games as g
  where g.id = confirm_score.game_id
  for update;

  if not found then
    raise exception 'GAME_NOT_FOUND' using errcode = 'P0002';
  end if;

  if game.status <> 'reported' then
    raise exception 'NOT_REPORTED' using errcode = '22023';
  end if;

  select exists (
    select from public.league_teams as t
    where t.captain_id = auth.uid()
      and t.id in (game.home_team_id, game.away_team_id)
      and t.id is distinct from game.reporting_team_id
  ) into opposing;

  select exists (
    select from public.league_seasons as s
    join public.group_members as m on m.group_id = s.group_id
    where s.id = game.season_id
      and m.user_id = auth.uid()
      and m.status = 'active'
      and m.role in ('owner', 'organizer')
  ) into organizer;

  if not (opposing or organizer) then
    raise exception 'NOT_OPPOSING_CAPTAIN' using errcode = '42501';
  end if;

  update public.league_games as g
  set status = 'confirmed', confirmed_by = auth.uid()
  where g.id = game.id;
end;
$$;

REVOKE EXECUTE ON FUNCTION public.confirm_score(uuid) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.confirm_score(uuid) TO authenticated;

-- An organizer sets a score, which is confirmed at once and audit-logged with the reason.
CREATE FUNCTION public.override_score(
  game_id uuid,
  home_score INTEGER,
  away_score INTEGER,
  reason text
)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
declare
  game public.league_games;
  clean_reason text := trim(override_score.reason);
begin
  select * into game
  from public.league_games as g
  where g.id = override_score.game_id
  for update;

  perform private.managed_season(game.season_id);

  if game.away_team_id is null then
    raise exception 'NOT_A_GAME' using errcode = '22023';
  end if;

  if char_length(clean_reason) not between 1 and 500 then
    raise exception 'REASON_REQUIRED' using errcode = '22023';
  end if;

  if override_score.home_score is null or override_score.away_score is null
    or override_score.home_score < 0 or override_score.away_score < 0
    or override_score.home_score > 999 or override_score.away_score > 999 then
    raise exception 'INVALID_SCORE' using errcode = '22023';
  end if;

  update public.league_games as g
  set
    home_score = override_score.home_score,
    away_score = override_score.away_score,
    status = 'confirmed',
    forfeit_team_id = null,
    confirmed_by = auth.uid()
  where g.id = game.id;

  perform private.audit(
    'override_score',
    'league_game',
    game.id,
    clean_reason,
    jsonb_build_object(
      'before', jsonb_build_object('status', game.status, 'home', game.home_score, 'away', game.away_score),
      'after', jsonb_build_object('home', override_score.home_score, 'away', override_score.away_score)
    )
  );
end;
$$;

REVOKE EXECUTE ON FUNCTION public.override_score(uuid, INTEGER, INTEGER, text) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.override_score(uuid, INTEGER, INTEGER, text) TO authenticated;

-- An organizer records that a team forfeited a game.
CREATE FUNCTION public.forfeit_game(game_id uuid, forfeit_team_id uuid)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
declare
  game public.league_games;
begin
  select * into game
  from public.league_games as g
  where g.id = forfeit_game.game_id
  for update;

  if not found then
    raise exception 'GAME_NOT_FOUND' using errcode = 'P0002';
  end if;

  perform private.managed_season(game.season_id);

  if game.away_team_id is null then
    raise exception 'NOT_A_GAME' using errcode = '22023';
  end if;

  if forfeit_game.forfeit_team_id is null
    or forfeit_game.forfeit_team_id not in (game.home_team_id, game.away_team_id) then
    raise exception 'NOT_IN_GAME' using errcode = '22023';
  end if;

  update public.league_games as g
  set
    status = 'forfeit',
    forfeit_team_id = forfeit_game.forfeit_team_id,
    home_score = null,
    away_score = null,
    confirmed_by = auth.uid()
  where g.id = game.id;
end;
$$;

REVOKE EXECUTE ON FUNCTION public.forfeit_game(uuid, uuid) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.forfeit_game(uuid, uuid) TO authenticated;

-- The audit log takes the override.
ALTER TABLE private.audit_log
DROP CONSTRAINT audit_log_action_check;

ALTER TABLE private.audit_log
ADD CONSTRAINT audit_log_action_check
  CHECK (
    action IN (
      'hide',
      'unhide',
      'suspend',
      'reinstate',
      'dismiss_report',
      'set_role',
      'delete_account',
      'data_fix',
      'transfer_activity',
      'cancel_activity',
      'set_board_activity',
      'announce_activity',
      'transfer_group',
      'override_score'
    )
  );

ALTER TABLE private.audit_log
DROP CONSTRAINT audit_log_target_type_check;

ALTER TABLE private.audit_log
ADD CONSTRAINT audit_log_target_type_check
  CHECK (
    target_type IN ('activity', 'profile', 'report', 'activity_update', 'group', 'league_game')
  );

-- Standings for a season: played, won, tied, lost, points and differential, from confirmed and
-- forfeited games only. A forfeit has no differential. Teams with no results still show, at zero.
CREATE FUNCTION public.season_standings(season_id uuid)
RETURNS TABLE (
  team_id uuid,
  team_name text,
  played INTEGER,
  won INTEGER,
  tied INTEGER,
  lost INTEGER,
  points INTEGER,
  differential INTEGER
)
LANGUAGE sql
STABLE
SECURITY INVOKER
SET search_path = ''
AS $$
  WITH
    results AS (
      SELECT
        g.home_team_id AS team_id,
        g.status,
        g.forfeit_team_id,
        g.home_score AS scored,
        g.away_score AS allowed
      FROM public.league_games AS g
      WHERE
        g.season_id = season_standings.season_id
        AND g.status IN ('confirmed', 'forfeit')
        AND g.away_team_id IS NOT NULL
      UNION ALL
      SELECT
        g.away_team_id,
        g.status,
        g.forfeit_team_id,
        g.away_score,
        g.home_score
      FROM public.league_games AS g
      WHERE
        g.season_id = season_standings.season_id
        AND g.status IN ('confirmed', 'forfeit')
        AND g.away_team_id IS NOT NULL
    ),
    outcomes AS (
      SELECT
        r.team_id,
        CASE
          WHEN r.status = 'forfeit' AND r.forfeit_team_id = r.team_id THEN 'L'
          WHEN r.status = 'forfeit' THEN 'W'
          WHEN r.scored > r.allowed THEN 'W'
          WHEN r.scored < r.allowed THEN 'L'
          ELSE 'T'
        END AS outcome,
        CASE WHEN r.status = 'forfeit' THEN 0 ELSE r.scored - r.allowed END AS diff
      FROM results AS r
    )
  SELECT
    t.id,
    t.name,
    COUNT(o.outcome)::INTEGER,
    (COUNT(*) FILTER (WHERE o.outcome = 'W'))::INTEGER,
    (COUNT(*) FILTER (WHERE o.outcome = 'T'))::INTEGER,
    (COUNT(*) FILTER (WHERE o.outcome = 'L'))::INTEGER,
    (
      COALESCE(
        SUM(
          CASE
            WHEN o.outcome = 'W' THEN s.points_win
            WHEN o.outcome = 'T' THEN s.points_tie
            ELSE s.points_loss
          END
        ),
        0
      )
    )::INTEGER,
    (COALESCE(SUM(o.diff), 0))::INTEGER
  FROM public.league_teams AS t
  JOIN public.league_seasons AS s ON s.id = t.season_id
  LEFT JOIN outcomes AS o ON o.team_id = t.id
  WHERE t.season_id = season_standings.season_id
  GROUP BY t.id, t.name
  ORDER BY 7 DESC, 8 DESC, 4 DESC, 2;
$$;

GRANT EXECUTE ON FUNCTION public.season_standings(uuid) TO authenticated;
