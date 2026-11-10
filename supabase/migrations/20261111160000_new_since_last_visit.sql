-- New since your last visit (ACT-11). Design document sections 7.4 and 10.3, and R-NOTIF-1. Home
-- marks the activities posted since the member's previous visit, instead of notifying everyone of
-- each one. A visit ends after 30 minutes away, so the markers stay put while a member browses, and
-- go once they come back later.

-- When the visit before this one ended. last_seen_at is when the member was last on Home.
ALTER TABLE public.profile_private
ADD COLUMN previous_visit_at timestamptz;

-- Notes that the signed-in member is on Home, and returns when their previous visit ended, or null
-- for their first. After 30 minutes away it's a new visit, and the one before it becomes the
-- previous visit. Within a visit it writes at most every 5 minutes.
CREATE FUNCTION public.record_visit()
RETURNS timestamptz
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
declare
  seen timestamptz;
  previous timestamptz;
begin
  if not private.is_active_member() then
    raise exception 'NOT_ACTIVE' using errcode = '42501';
  end if;

  select pp.last_seen_at, pp.previous_visit_at into seen, previous
  from public.profile_private as pp
  where pp.user_id = auth.uid()
  for update;

  if seen is null or seen < now() - interval '30 minutes' then
    update public.profile_private as pp
    set previous_visit_at = seen, last_seen_at = now()
    where pp.user_id = auth.uid();
    return seen;
  end if;

  if seen < now() - interval '5 minutes' then
    update public.profile_private as pp set last_seen_at = now() where pp.user_id = auth.uid();
  end if;

  return previous;
end;
$$;

GRANT EXECUTE ON FUNCTION public.record_visit() TO authenticated;
