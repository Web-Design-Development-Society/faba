-- No limit on starting groups (GRP-06). create_group() is as it was (GRP-01), without the check
-- that refused a fourth group in 30 days. Only active members can start one, a double tap still
-- makes one group, and reports and moderators handle a bad one (MOD-08). Its grants stay.
CREATE OR REPLACE FUNCTION public.create_group(
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
