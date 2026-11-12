-- The individual ladder (LEAG-08). In a ladder season, players sign up rather than teams. Entering
-- the ladder makes each player a team of one, with the player as its captain, so the round robin,
-- score reports and standings (LEAG-04 and LEAG-05) work for one-on-one games as they do for teams.
-- Each game is between two players, and standings come from confirmed results only.

-- Makes a one-person team for each player who signed up and isn't on one yet. Returns how many.
CREATE FUNCTION public.enter_ladder(season_id uuid)
RETURNS INTEGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
declare
  s public.league_seasons := private.managed_season(enter_ladder.season_id);
  offset_by INTEGER;
  made INTEGER := 0;
  entry record;
  team uuid;
begin
  if s.format <> 'ladder' then
    raise exception 'NOT_A_LADDER' using errcode = '22023';
  end if;

  select count(*)::INTEGER into offset_by
  from public.league_teams as t
  where t.season_id = s.id;

  for entry in
    select
      r.user_id,
      coalesce(nullif(trim(p.display_name), ''), 'Player') as display_name,
      row_number() over (order by r.created_at)::INTEGER as seq
    from public.league_registrations as r
    join public.profiles as p on p.id = r.user_id
    where r.season_id = s.id and r.kind = 'player' and r.team_id is null
    order by r.created_at
  loop
    insert into public.league_teams (season_id, name, color, captain_id)
    values (
      s.id,
      left(entry.display_name, 30) || ' (' || (offset_by + entry.seq) || ')',
      '#1d76db',
      entry.user_id
    )
    returning id into team;

    update public.league_registrations as r
    set team_id = team
    where r.season_id = s.id and r.user_id = entry.user_id;

    made := made + 1;
  end loop;

  return made;
end;
$$;

REVOKE EXECUTE ON FUNCTION public.enter_ladder(uuid) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.enter_ladder(uuid) TO authenticated;
