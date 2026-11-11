-- Registering for a season (LEAG-02). A member signs up as a player or a free agent, with an
-- optional note. Registering also joins the league group. Withdrawing is allowed until the
-- organizers set the teams (LEAG-03); after that, the member asks the organizer.

-- Teams, which LEAG-03 fills in. They're created here because withdrawing depends on whether any
-- exist.
CREATE TABLE public.league_teams (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  season_id uuid NOT NULL REFERENCES public.league_seasons (id)
    ON DELETE CASCADE,
  name text NOT NULL CHECK (char_length(trim(name)) BETWEEN 1 AND 40),
  color text NOT NULL CHECK (color ~ '^#[0-9a-fA-F]{6}$'),
  captain_id uuid REFERENCES public.profiles (id)
    ON DELETE SET NULL,
  created_at timestamptz NOT NULL DEFAULT now(),
  UNIQUE (season_id, name)
);

ALTER TABLE public.league_teams ENABLE ROW LEVEL SECURITY;

CREATE TABLE public.league_registrations (
  season_id uuid NOT NULL REFERENCES public.league_seasons (id)
    ON DELETE CASCADE,
  user_id uuid NOT NULL REFERENCES public.profiles (id)
    ON DELETE CASCADE,
  kind text NOT NULL CHECK (kind IN ('player', 'free_agent')),
  note text CHECK (char_length(note) <= 280),
  created_at timestamptz NOT NULL DEFAULT now(),
  PRIMARY KEY (season_id, user_id)
);

CREATE INDEX league_registrations_user_idx ON public.league_registrations (user_id);

ALTER TABLE public.league_registrations ENABLE ROW LEVEL SECURITY;

-- Who can see a season's teams and registrations: moderators, and active members of a league that
-- isn't hidden. The same as the seasons themselves.
CREATE FUNCTION private.can_see_season(season_id uuid)
RETURNS BOOLEAN
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = ''
AS $$
  SELECT private.is_moderator()
  OR (
    private.is_active_member()
    AND EXISTS (
      SELECT
      FROM public.league_seasons AS s
      JOIN public.groups AS g ON g.id = s.group_id
      WHERE s.id = can_see_season.season_id AND g.hidden_at IS NULL
    )
  );
$$;

REVOKE EXECUTE ON FUNCTION private.can_see_season(uuid) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION private.can_see_season(uuid) TO authenticated;

CREATE POLICY "Members read teams of visible leagues" ON public.league_teams
FOR SELECT
TO authenticated
USING (private.can_see_season(league_teams.season_id));

CREATE POLICY "Members read registrations of visible leagues" ON public.league_registrations
FOR SELECT
TO authenticated
USING (private.can_see_season(league_registrations.season_id));

-- Signs up for a season as a player or a free agent. Makes the member a member of the league's
-- group too, or a pending one in an approval group. Changing the answer works until teams are set.
CREATE FUNCTION public.join_season(season_id uuid, kind text, note text DEFAULT NULL)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
declare
  s public.league_seasons;
  g public.groups;
  clean_note text := nullif(trim(join_season.note), '');
begin
  if not private.is_active_member() then
    raise exception 'NOT_ACTIVE' using errcode = '42501';
  end if;

  select * into s
  from public.league_seasons as x
  where x.id = join_season.season_id;

  if not found then
    raise exception 'SEASON_NOT_FOUND' using errcode = 'P0002';
  end if;

  select * into g
  from public.groups as x
  where x.id = s.group_id;

  if g.kind <> 'league' or (g.hidden_at is not null and not private.is_moderator()) then
    raise exception 'SEASON_NOT_FOUND' using errcode = 'P0002';
  end if;

  if g.archived_at is not null then
    raise exception 'GROUP_ARCHIVED' using errcode = '22023';
  end if;

  if not s.registration_open then
    raise exception 'REGISTRATION_CLOSED' using errcode = '22023';
  end if;

  if join_season.kind is null or join_season.kind not in ('player', 'free_agent') then
    raise exception 'INVALID_REGISTRATION' using errcode = '22023';
  end if;

  if exists (select from public.league_teams as t where t.season_id = s.id) then
    raise exception 'TEAMS_SET' using errcode = '22023';
  end if;

  if not exists (
    select from public.group_members as m
    where m.group_id = g.id and m.user_id = auth.uid()
  ) then
    insert into public.group_members (group_id, user_id, status)
    values (
      g.id,
      auth.uid(),
      case when g.join_policy = 'open' then 'active' else 'pending' end
    );
  end if;

  insert into public.league_registrations (season_id, user_id, kind, note)
  values (s.id, auth.uid(), join_season.kind, clean_note)
  on conflict on constraint league_registrations_pkey do update
  set kind = excluded.kind, note = excluded.note;
end;
$$;

REVOKE EXECUTE ON FUNCTION public.join_season(uuid, text, text) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.join_season(uuid, text, text) TO authenticated;

-- Withdraws from a season, which is allowed until teams are set. Doesn't leave the league group.
CREATE FUNCTION public.withdraw_from_season(season_id uuid)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
begin
  if exists (select from public.league_teams as t where t.season_id = withdraw_from_season.season_id) then
    raise exception 'TEAMS_SET' using errcode = '22023';
  end if;

  delete from public.league_registrations as r
  where r.season_id = withdraw_from_season.season_id and r.user_id = auth.uid();
end;
$$;

REVOKE EXECUTE ON FUNCTION public.withdraw_from_season(uuid) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.withdraw_from_season(uuid) TO authenticated;
