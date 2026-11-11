-- Game availability (LEAG-07). A player says whether they can play a game, and that answer is their
-- RSVP for the game's activity: "Can play" is going, and "Can't play" is not going. So games show up
-- in Plans like any other activity, and the RSVP model is reused. Captains see their roster's answers.
-- The only players who can answer are the ones on a game's teams, and subs for it.

CREATE TABLE public.league_game_availability (
  game_id uuid NOT NULL REFERENCES public.league_games (id)
    ON DELETE CASCADE,
  user_id uuid NOT NULL REFERENCES public.profiles (id)
    ON DELETE CASCADE,
  can_play BOOLEAN NOT NULL,
  updated_at timestamptz NOT NULL DEFAULT now(),
  PRIMARY KEY (game_id, user_id)
);

ALTER TABLE public.league_game_availability ENABLE ROW LEVEL SECURITY;

-- The league's members read the answers for the games they can see. Writes go through
-- set_game_availability().
CREATE POLICY "Members read availability of visible leagues" ON public.league_game_availability
FOR SELECT
TO authenticated
USING (
  EXISTS (
    SELECT
    FROM public.league_games AS g
    WHERE g.id = league_game_availability.game_id AND private.can_see_season(g.season_id)
  )
);

-- Says whether the signed-in player can play `game_id`, and sets their RSVP to match.
CREATE FUNCTION public.set_game_availability(game_id uuid, can_play BOOLEAN)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
declare
  g public.league_games;
  playing boolean;
begin
  if not private.is_active_member() then
    raise exception 'NOT_ACTIVE' using errcode = '42501';
  end if;

  select * into g
  from public.league_games as x
  where x.id = set_game_availability.game_id;

  if not found then
    raise exception 'GAME_NOT_FOUND' using errcode = 'P0002';
  end if;

  if g.activity_id is null then
    raise exception 'NOT_A_GAME' using errcode = '22023';
  end if;

  if g.status <> 'scheduled' then
    raise exception 'GAME_LOCKED' using errcode = '22023';
  end if;

  playing := exists (
    select from public.league_registrations as r
    where r.season_id = g.season_id
      and r.user_id = auth.uid()
      and r.kind = 'player'
      and r.team_id in (g.home_team_id, g.away_team_id)
  ) or exists (
    select from public.league_game_subs as s
    where s.game_id = g.id and s.user_id = auth.uid()
  );

  if not playing then
    raise exception 'NOT_PLAYING_IN_GAME' using errcode = '42501';
  end if;

  insert into public.league_game_availability (game_id, user_id, can_play, updated_at)
  values (g.id, auth.uid(), set_game_availability.can_play, now())
  on conflict on constraint league_game_availability_pkey do update
  set can_play = excluded.can_play, updated_at = excluded.updated_at;

  -- The same answer is the RSVP, so the game is in the player's Plans.
  perform public.rsvp(g.activity_id, case when set_game_availability.can_play then 'going' else 'not_going' end);
end;
$$;

REVOKE EXECUTE ON FUNCTION public.set_game_availability(uuid, BOOLEAN) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.set_game_availability(uuid, BOOLEAN) TO authenticated;
