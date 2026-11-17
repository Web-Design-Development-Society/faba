-- Joining a group follows it (GRP-02, NOTIF-09). Whenever a membership becomes active (joining an
-- open group, being approved, starting a group, signing up for a league season) the member follows
-- the group, so they hear about its new activities. They can still unfollow with the group's
-- Following button. Leaving, being removed, or the group being deleted drops the follow, so someone
-- who left doesn't quietly follow again when they rejoin, and no follow outlives its group.
CREATE FUNCTION private.follow_group_on_join()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
begin
  -- The old membership is gone, or now belongs to someone or somewhere else (merging accounts).
  if tg_op = 'DELETE'
    or (tg_op = 'UPDATE' and (old.group_id, old.user_id) is distinct from (new.group_id, new.user_id))
  then
    delete from public.follows as f
    where
      f.user_id = old.user_id
      and f.target_type = 'group'
      and f.target_id = old.group_id::text;
  end if;

  if tg_op = 'DELETE' then
    return old;
  end if;

  -- A membership that has just become active.
  if new.status = 'active'
    and (
      tg_op = 'INSERT'
      or old.status <> 'active'
      or (old.group_id, old.user_id) is distinct from (new.group_id, new.user_id)
    )
  then
    insert into public.follows (user_id, target_type, target_id)
    values (new.user_id, 'group', new.group_id::text)
    on conflict (user_id, target_type, target_id) do nothing;
  end if;

  return new;
end;
$$;

CREATE TRIGGER follow_group_on_join
AFTER INSERT OR UPDATE OR DELETE ON public.group_members
FOR EACH ROW
EXECUTE FUNCTION private.follow_group_on_join();

-- Members who joined before this follow their groups now, as GRP-02 always said they would.
INSERT INTO public.follows (user_id, target_type, target_id)
SELECT m.user_id, 'group', m.group_id::text
FROM public.group_members AS m
WHERE m.status = 'active'
ON CONFLICT (user_id, target_type, target_id) DO NOTHING;

-- Follows of groups that no longer exist, or that the member has left.
DELETE FROM public.follows AS f
WHERE
  f.target_type = 'group'
  AND NOT EXISTS (
    SELECT
    FROM public.group_members AS m
    WHERE m.user_id = f.user_id AND m.group_id::text = f.target_id
  );
