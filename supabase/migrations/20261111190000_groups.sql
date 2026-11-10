-- Interest groups (GRP-01). Design document sections 7.3, 8.7 and 10.3, and FR-GRP-1. A member
-- starts a group with a name, a description, a category and a join policy, and becomes its owner.
-- Each member can start 3 groups in 30 days. Joining and leaving come with GRP-02, organizers and
-- ownership transfer with GRP-05, and auto-archiving with GRP-04 and GRP-05.

CREATE TABLE public.groups (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  -- For the group's address, /groups/<slug>, made from its name.
  slug text NOT NULL UNIQUE CHECK (slug ~ '^[a-z0-9]+(-[a-z0-9]+)*$'),
  name text NOT NULL CHECK (char_length(name) BETWEEN 3 AND 60),
  description text CHECK (char_length(description) <= 1000),
  category_id text NOT NULL REFERENCES public.categories (id),
  -- Leagues are groups too, in Phase 4.
  kind text NOT NULL DEFAULT 'interest' CHECK (kind IN ('interest', 'league')),
  join_policy text NOT NULL DEFAULT 'open' CHECK (join_policy IN ('open', 'approval')),
  -- The group stays when its owner deletes their account, until GRP-05 hands it on.
  owner_id uuid REFERENCES public.profiles (id)
    ON DELETE SET NULL,
  idempotency_key uuid,
  archived_at timestamptz,
  hidden_at timestamptz,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now()
);

CREATE INDEX groups_kind_archived_idx ON public.groups (kind, archived_at);

-- Starting the same group twice finds the first, and counting a member's new groups is quick.
CREATE UNIQUE INDEX groups_owner_idempotency_idx ON public.groups (owner_id, idempotency_key);

CREATE INDEX groups_owner_created_idx ON public.groups (owner_id, created_at);

CREATE INDEX groups_category_idx ON public.groups (category_id);

CREATE TRIGGER groups_set_updated_at
BEFORE UPDATE ON public.groups
FOR EACH ROW
EXECUTE FUNCTION private.set_updated_at();

CREATE TABLE public.group_members (
  group_id uuid NOT NULL REFERENCES public.groups (id)
    ON DELETE CASCADE,
  user_id uuid NOT NULL REFERENCES public.profiles (id)
    ON DELETE CASCADE,
  role text NOT NULL DEFAULT 'member' CHECK (role IN ('owner', 'organizer', 'member')),
  -- Pending until an organizer approves them, in an approval group (GRP-02).
  status text NOT NULL DEFAULT 'active' CHECK (status IN ('active', 'pending')),
  joined_at timestamptz NOT NULL DEFAULT now(),
  PRIMARY KEY (group_id, user_id)
);

CREATE INDEX group_members_user_idx ON public.group_members (user_id, status);

-- True when the signed-in member is an active member of `group_id`. It reads group_members as its
-- owner, so group_members' own policy can use it.
CREATE FUNCTION private.is_group_member(group_id uuid)
RETURNS BOOLEAN
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = ''
AS $$
  SELECT EXISTS (
    SELECT
    FROM public.group_members AS m
    WHERE m.group_id = is_group_member.group_id AND m.user_id = auth.uid() AND m.status = 'active'
  );
$$;

REVOKE EXECUTE ON FUNCTION private.is_group_member(uuid) FROM PUBLIC, anon, service_role;

GRANT EXECUTE ON FUNCTION private.is_group_member(uuid) TO authenticated;

ALTER TABLE public.groups ENABLE ROW LEVEL SECURITY;

ALTER TABLE public.group_members ENABLE ROW LEVEL SECURITY;

-- Section 10.3: active members read groups, but only its owner and moderators read a hidden one.
-- They're changed only through functions.
CREATE POLICY "Active members read groups that aren't hidden" ON public.groups
FOR SELECT
TO authenticated
USING (
  private.is_active_member()
  AND (hidden_at IS NULL OR owner_id = (SELECT auth.uid()) OR private.is_moderator())
);

-- A member reads their own memberships, and the members of the groups they're in.
CREATE POLICY "Members read their own memberships and their groups' members" ON public.group_members
FOR SELECT
TO authenticated
USING (
  user_id = (SELECT auth.uid())
  OR (private.is_active_member() AND private.is_group_member(group_id))
);

-- `name` as an address: lowercase letters and numbers, with hyphens between words, at most 50
-- characters. A name with none of those gives "group".
CREATE FUNCTION private.slugify(name text)
RETURNS text
LANGUAGE sql
IMMUTABLE
SET search_path = ''
AS $$
  SELECT coalesce(
    nullif(
      trim(BOTH '-' FROM left(
        trim(BOTH '-' FROM regexp_replace(lower(name), '[^a-z0-9]+', '-', 'g')),
        50
      )),
      ''
    ),
    'group'
  );
$$;

REVOKE EXECUTE ON FUNCTION private.slugify(text) FROM PUBLIC, anon, authenticated, service_role;

-- Starts a group and makes the signed-in member its owner. Returns its slug. Starting it again with
-- the same idempotency key returns the first one's.
CREATE FUNCTION public.create_group(
  name text,
  category_id text,
  description text DEFAULT NULL,
  join_policy text DEFAULT 'open',
  idempotency_key uuid DEFAULT NULL
)
RETURNS text
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
declare
  clean text := trim(create_group.name);
  base text;
  new_slug text;
  new_id uuid;
  n integer := 1;
begin
  if not private.is_active_member() then
    raise exception 'NOT_ACTIVE' using errcode = '42501';
  end if;

  -- One at a time per member, so two taps can't both pass the checks below.
  perform pg_advisory_xact_lock(hashtextextended('create_group ' || auth.uid(), 0));

  if create_group.idempotency_key is not null then
    select g.slug into new_slug
    from public.groups as g
    where g.owner_id = auth.uid() and g.idempotency_key = create_group.idempotency_key;

    if found then
      return new_slug;
    end if;
  end if;

  if char_length(clean) not between 3 and 60 then
    raise exception 'INVALID_GROUP_NAME' using errcode = '22023';
  end if;

  if char_length(trim(create_group.description)) > 1000 then
    raise exception 'INVALID_GROUP_DESCRIPTION' using errcode = '22023';
  end if;

  if create_group.join_policy is null or create_group.join_policy not in ('open', 'approval') then
    raise exception 'INVALID_JOIN_POLICY' using errcode = '22023';
  end if;

  if not exists (
    select from public.categories as c
    where c.id = create_group.category_id and c.is_active
  ) then
    raise exception 'INVALID_CATEGORY' using errcode = '22023';
  end if;

  -- At most 3 in 30 days (GRP-01).
  if (
    select count(*)
    from public.groups as g
    where g.owner_id = auth.uid() and g.created_at > now() - interval '30 days'
  ) >= 3 then
    raise exception 'GROUP_QUOTA_EXCEEDED' using errcode = 'P0001';
  end if;

  -- trail-runners, then trail-runners-2 and so on when it's taken.
  base := private.slugify(clean);
  new_slug := base;
  while exists (select from public.groups as g where g.slug = new_slug) loop
    n := n + 1;
    new_slug := base || '-' || n;
  end loop;

  insert into public.groups (slug, name, description, category_id, join_policy, owner_id, idempotency_key)
  values (
    new_slug,
    clean,
    nullif(trim(create_group.description), ''),
    create_group.category_id,
    create_group.join_policy,
    auth.uid(),
    create_group.idempotency_key
  )
  returning id into new_id;

  insert into public.group_members (group_id, user_id, role)
  values (new_id, auth.uid(), 'owner');

  return new_slug;
end;
$$;

GRANT EXECUTE ON FUNCTION public.create_group(text, text, text, text, uuid) TO authenticated;

-- Moving a member to a new account as before (20261109130000_activity_updates.sql), with the groups
-- they own and belong to. Where both accounts are in a group, the new one keeps the higher role,
-- and stays active if either was.
CREATE OR REPLACE FUNCTION private.transfer_account(from_user uuid, to_user uuid, reason text)
RETURNS void
LANGUAGE plpgsql
SET search_path = ''
AS $$
declare
  why text := nullif(trim(transfer_account.reason), '');
  organized integer;
  moved integer;
  dropped integer;
  owned integer;
  memberships integer;
begin
  if why is null then
    raise exception 'REASON_REQUIRED' using errcode = '22023';
  end if;

  if from_user = to_user then
    raise exception 'SAME_ACCOUNT' using errcode = '22023';
  end if;

  if (select count(*) from public.profiles as p where p.id in (from_user, to_user)) < 2 then
    raise exception 'MEMBER_NOT_FOUND' using errcode = 'P0002';
  end if;

  update public.activities as a
  set organizer_id = to_user
  where a.organizer_id = from_user;
  get diagnostics organized = row_count;

  update public.activity_updates as u
  set author_id = to_user
  where u.author_id = from_user;

  -- RSVPs to an activity the new account has also answered go, with the going or maybe count and
  -- the guests they held.
  update public.activities as a
  set
    going_count = a.going_count - (r.status = 'going')::integer,
    maybe_count = a.maybe_count - (r.status = 'maybe')::integer,
    guest_total = a.guest_total - r.guest_count
  from public.rsvps as r
  where
    r.activity_id = a.id
    and r.user_id = from_user
    and r.status in ('going', 'maybe')
    and exists (
      select from public.rsvps as mine where mine.activity_id = a.id and mine.user_id = to_user
    );

  delete from public.rsvps as r
  where
    r.user_id = from_user
    and exists (
      select from public.rsvps as mine
      where mine.activity_id = r.activity_id and mine.user_id = to_user
    );
  get diagnostics dropped = row_count;

  update public.rsvps as r
  set user_id = to_user
  where r.user_id = from_user;
  get diagnostics moved = row_count;

  -- GRP-01: the groups they own, and their memberships.
  update public.groups as g
  set owner_id = to_user
  where g.owner_id = from_user;
  get diagnostics owned = row_count;

  update public.group_members as mine
  set
    role = case
      when 'owner' in (mine.role, old.role) then 'owner'
      when 'organizer' in (mine.role, old.role) then 'organizer'
      else 'member'
    end,
    status = case when 'active' in (mine.status, old.status) then 'active' else 'pending' end
  from public.group_members as old
  where old.group_id = mine.group_id and old.user_id = from_user and mine.user_id = to_user;

  delete from public.group_members as old
  where
    old.user_id = from_user
    and exists (
      select from public.group_members as mine
      where mine.group_id = old.group_id and mine.user_id = to_user
    );

  update public.group_members as m
  set user_id = to_user
  where m.user_id = from_user;
  get diagnostics memberships = row_count;

  perform private.audit(
    'data_fix',
    'profile',
    from_user,
    why,
    jsonb_build_object(
      'transferred_to', to_user,
      'activities', organized,
      'rsvps_moved', moved,
      'rsvps_dropped', dropped,
      'groups_owned', owned,
      'group_memberships_moved', memberships
    )
  );
end;
$$;
