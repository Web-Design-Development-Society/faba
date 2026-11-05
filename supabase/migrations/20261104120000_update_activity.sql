-- Editing an activity (ACT-04). Design document sections 9.9, 10.3 and 10.5.

-- When the start, end or place last changed, for the "Updated" label (ACT-04) and, in Phase 2,
-- the change notifications (NOTIF-02). updated_at doesn't do, since every RSVP changes it.
ALTER TABLE public.activities
ADD COLUMN time_or_place_changed_at timestamptz;

-- Changes an activity. `patch` holds the fields that change, with the values create_activity()
-- takes, and a null clears an optional one. Only its organizer can, and only from the version they
-- saw, so a save from an older page fails with STALE_EDIT (section 9.9). Once it has started, only
-- the description can change (FR-ACT-4). Before that, create_activity()'s rules apply. An organizer
-- can still edit it when it's cancelled or hidden.
CREATE FUNCTION public.update_activity(activity_id uuid, patch jsonb, expected_version INTEGER)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
declare
  saved public.activities;
  changed public.activities;
begin
  if not private.is_active_member() then
    raise exception 'NOT_ACTIVE' using errcode = '42501';
  end if;

  if patch - array[
    'title', 'category_id', 'starts_at', 'ends_at', 'location_name', 'description', 'cost_note'
  ] != '{}'::jsonb then
    raise exception 'INVALID_FIELD' using errcode = '22023';
  end if;

  select * into saved
  from public.activities as a
  where a.id = update_activity.activity_id
  for update;

  -- The same for an activity that doesn't exist, so nobody learns which ones do.
  if not found or saved.organizer_id is distinct from auth.uid() then
    raise exception 'NOT_ORGANIZER' using errcode = '42501';
  end if;

  if saved.version != update_activity.expected_version then
    raise exception 'STALE_EDIT' using errcode = '40001';
  end if;

  changed := jsonb_populate_record(saved, patch);
  changed.title := trim(changed.title);
  changed.description := nullif(trim(changed.description), '');
  changed.location_name := trim(changed.location_name);
  changed.cost_note := nullif(trim(changed.cost_note), '');

  if saved.starts_at <= now() then
    if (
      changed.title,
      changed.category_id,
      changed.starts_at,
      changed.ends_at,
      changed.location_name,
      changed.cost_note
    ) is distinct from (
      saved.title,
      saved.category_id,
      saved.starts_at,
      saved.ends_at,
      saved.location_name,
      saved.cost_note
    ) then
      raise exception 'ACTIVITY_STARTED' using errcode = '22023';
    end if;
  else
    -- An activity keeps a category that's no longer offered until it's changed.
    if changed.category_id != saved.category_id and not exists (
      select from public.categories as c
      where c.id = changed.category_id and c.is_active
    ) then
      raise exception 'INVALID_CATEGORY' using errcode = '22023';
    end if;

    if changed.starts_at <= now() then
      raise exception 'START_IN_PAST' using errcode = '22023';
    end if;

    if changed.starts_at > now() + interval '12 months' then
      raise exception 'START_TOO_FAR' using errcode = '22023';
    end if;

    if changed.ends_at <= changed.starts_at then
      raise exception 'END_BEFORE_START' using errcode = '22023';
    end if;
  end if;

  update public.activities as a
  set
    title = changed.title,
    category_id = changed.category_id,
    description = changed.description,
    starts_at = changed.starts_at,
    ends_at = changed.ends_at,
    location_name = changed.location_name,
    cost_note = changed.cost_note,
    time_or_place_changed_at = case
      when (changed.starts_at, changed.ends_at, changed.location_name)
        is distinct from (saved.starts_at, saved.ends_at, saved.location_name)
      then now()
      else a.time_or_place_changed_at
    end,
    version = a.version + 1
  where a.id = saved.id;
end;
$$;

GRANT EXECUTE ON FUNCTION public.update_activity(uuid, jsonb, INTEGER) TO authenticated;
