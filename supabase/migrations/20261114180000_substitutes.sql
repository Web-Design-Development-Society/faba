-- Requesting a substitute (LEAG-06). A captain needs a sub for a game, and every free agent in the
-- season hears about it. The first free agent to accept is added to that game only. A game takes
-- one sub request an hour, so the requests can't flood the free agents.

CREATE TABLE public.league_sub_requests (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  season_id uuid NOT NULL REFERENCES public.league_seasons (id)
    ON DELETE CASCADE,
  game_id uuid NOT NULL REFERENCES public.league_games (id)
    ON DELETE CASCADE,
  team_id uuid NOT NULL REFERENCES public.league_teams (id)
    ON DELETE CASCADE,
  requested_by uuid REFERENCES public.profiles (id)
    ON DELETE SET NULL,
  filled_by uuid REFERENCES public.profiles (id)
    ON DELETE SET NULL,
  filled_at timestamptz,
  created_at timestamptz NOT NULL DEFAULT now(),
  CONSTRAINT sub_filled_together CHECK ((filled_by IS NULL) = (filled_at IS NULL))
);

-- One open request per team in a game.
CREATE UNIQUE INDEX league_sub_requests_open_idx ON public.league_sub_requests (game_id, team_id)
WHERE filled_by IS NULL;

CREATE INDEX league_sub_requests_game_idx ON public.league_sub_requests (game_id, created_at);

ALTER TABLE public.league_sub_requests ENABLE ROW LEVEL SECURITY;

CREATE POLICY "Members read sub requests of visible leagues" ON public.league_sub_requests
FOR SELECT
TO authenticated
USING (private.can_see_season(league_sub_requests.season_id));

-- The subs who play a game, one per team. A person subs for one team in a game.
CREATE TABLE public.league_game_subs (
  game_id uuid NOT NULL REFERENCES public.league_games (id)
    ON DELETE CASCADE,
  team_id uuid NOT NULL REFERENCES public.league_teams (id)
    ON DELETE CASCADE,
  user_id uuid NOT NULL REFERENCES public.profiles (id)
    ON DELETE CASCADE,
  request_id uuid REFERENCES public.league_sub_requests (id)
    ON DELETE SET NULL,
  created_at timestamptz NOT NULL DEFAULT now(),
  PRIMARY KEY (game_id, team_id),
  UNIQUE (game_id, user_id)
);

ALTER TABLE public.league_game_subs ENABLE ROW LEVEL SECURITY;

CREATE POLICY "Members read subs of visible leagues" ON public.league_game_subs
FOR SELECT
TO authenticated
USING (
  EXISTS (
    SELECT
    FROM public.league_games AS g
    WHERE g.id = league_game_subs.game_id AND private.can_see_season(g.season_id)
  )
);

-- Asks the season's free agents for a sub, for a game of the captain's team.
CREATE FUNCTION public.request_sub(game_id uuid)
RETURNS uuid
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
declare
  g public.league_games;
  mine uuid := private.captain_team(request_sub.game_id);
  starts timestamptz;
  team_name text;
  request_id uuid;
begin
  select * into g
  from public.league_games as x
  where x.id = request_sub.game_id
  for update;

  if not found then
    raise exception 'GAME_NOT_FOUND' using errcode = 'P0002';
  end if;

  if g.away_team_id is null then
    raise exception 'NOT_A_GAME' using errcode = '22023';
  end if;

  if mine is null then
    raise exception 'NOT_CAPTAIN' using errcode = '42501';
  end if;

  if g.status <> 'scheduled' then
    raise exception 'GAME_LOCKED' using errcode = '22023';
  end if;

  select a.starts_at into starts
  from public.activities as a
  where a.id = g.activity_id;

  if starts <= now() then
    raise exception 'GAME_STARTED' using errcode = '22023';
  end if;

  if exists (
    select from public.league_sub_requests as r
    where r.game_id = g.id and r.created_at > now() - interval '1 hour'
  ) then
    raise exception 'SUB_RATE_LIMITED' using errcode = '53400';
  end if;

  if exists (
    select from public.league_sub_requests as r
    where r.game_id = g.id and r.team_id = mine and r.filled_by is null
  ) then
    raise exception 'SUB_ALREADY_REQUESTED' using errcode = '22023';
  end if;

  select t.name into team_name
  from public.league_teams as t
  where t.id = mine;

  insert into public.league_sub_requests (season_id, game_id, team_id, requested_by)
  values (g.season_id, g.id, mine, auth.uid())
  returning id into request_id;

  perform private.notify(
    array(
      select r.user_id
      from public.league_registrations as r
      join public.profiles as p on p.id = r.user_id
      where r.season_id = g.season_id
        and r.kind = 'free_agent'
        and p.status = 'active'
        and r.user_id <> auth.uid()
    ),
    'sub_needed',
    g.activity_id,
    jsonb_build_object('team', team_name),
    'sub_needed:' || request_id
  );

  return request_id;
end;
$$;

REVOKE EXECUTE ON FUNCTION public.request_sub(uuid) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.request_sub(uuid) TO authenticated;

-- A free agent accepts a sub request. The first to accept is added to that game only.
CREATE FUNCTION public.accept_sub(request_id uuid)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
declare
  r public.league_sub_requests;
  g public.league_games;
  starts timestamptz;
begin
  if not private.is_active_member() then
    raise exception 'NOT_ACTIVE' using errcode = '42501';
  end if;

  select * into r
  from public.league_sub_requests as x
  where x.id = accept_sub.request_id
  for update;

  if not found then
    raise exception 'SUB_REQUEST_NOT_FOUND' using errcode = 'P0002';
  end if;

  if r.filled_by is not null then
    raise exception 'SUB_FILLED' using errcode = '22023';
  end if;

  if not exists (
    select from public.league_registrations as x
    where x.season_id = r.season_id and x.user_id = auth.uid() and x.kind = 'free_agent'
  ) then
    raise exception 'NOT_FREE_AGENT' using errcode = '42501';
  end if;

  select * into g
  from public.league_games as x
  where x.id = r.game_id;

  if g.status <> 'scheduled' then
    raise exception 'GAME_LOCKED' using errcode = '22023';
  end if;

  select a.starts_at into starts
  from public.activities as a
  where a.id = g.activity_id;

  if starts <= now() then
    raise exception 'GAME_STARTED' using errcode = '22023';
  end if;

  if exists (
    select from public.league_registrations as x
    where x.season_id = r.season_id
      and x.user_id = auth.uid()
      and x.team_id in (g.home_team_id, g.away_team_id)
  ) or exists (
    select from public.league_game_subs as s
    where s.game_id = g.id and s.user_id = auth.uid()
  ) then
    raise exception 'ALREADY_PLAYING' using errcode = '22023';
  end if;

  insert into public.league_game_subs (game_id, team_id, user_id, request_id)
  values (g.id, r.team_id, auth.uid(), r.id);

  update public.league_sub_requests as x
  set filled_by = auth.uid(), filled_at = now()
  where x.id = r.id;
end;
$$;

REVOKE EXECUTE ON FUNCTION public.accept_sub(uuid) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.accept_sub(uuid) TO authenticated;

-- The notification type for a sub request. The list is the types on main at the time (including
-- new_activity from NOTIF-09), so later branches that add types must list theirs too.
ALTER TABLE public.notifications
DROP CONSTRAINT notifications_type_check;

ALTER TABLE public.notifications
ADD CONSTRAINT notifications_type_check
  CHECK (
    type IN (
      'activity_changed',
      'activity_cancelled',
      'activity_restored',
      'organizer_update',
      'rsvp_confirmed',
      'new_attendees',
      'reminder',
      'board_announcement',
      'group_join_request',
      'group_update',
      'group_join_approved',
      'group_owner',
      'rsvp_promoted',
      'rsvp_removed',
      'new_activity',
      'sub_needed'
    )
  );
