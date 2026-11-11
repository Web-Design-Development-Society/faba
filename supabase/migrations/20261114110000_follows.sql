-- Following categories and groups (NOTIF-09). Design document sections 8.8, 9.12 and 10.4. A member
-- follows a category or a group. When someone posts an activity there, each follower hears about
-- it, at most once a day per follow: "2 new Outdoors activities". A category's follows hear only
-- about activities everyone in FABA can see, not group-only ones.

CREATE TABLE public.follows (
  user_id uuid NOT NULL REFERENCES public.profiles (id)
    ON DELETE CASCADE,
  target_type text NOT NULL CHECK (target_type IN ('category', 'group')),
  -- A category's id, or a group's id as text.
  target_id text NOT NULL,
  created_at timestamptz NOT NULL DEFAULT now(),
  PRIMARY KEY (user_id, target_type, target_id)
);

CREATE INDEX follows_target_idx ON public.follows (target_type, target_id);

ALTER TABLE public.follows ENABLE ROW LEVEL SECURITY;

-- Members read their own follows. Writes go through set_follow().
CREATE POLICY "Members read their own follows" ON public.follows
FOR SELECT
TO authenticated
USING (user_id = (SELECT auth.uid()));

-- Follows or unfollows a category or group for the signed-in member. A category must be active,
-- and a group must not be hidden or archived. Returns whether they now follow it.
CREATE FUNCTION public.set_follow(kind text, target text, follow BOOLEAN)
RETURNS BOOLEAN
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
begin
  if not private.is_active_member() then
    raise exception 'NOT_ACTIVE' using errcode = '42501';
  end if;

  if kind = 'category' then
    if not exists (
      select from public.categories as c where c.id = set_follow.target and c.is_active
    ) then
      raise exception 'CATEGORY_NOT_FOUND' using errcode = 'P0002';
    end if;
  elsif kind = 'group' then
    if not exists (
      select from public.groups as g
      where g.id::text = set_follow.target and g.hidden_at is null and g.archived_at is null
    ) then
      raise exception 'GROUP_NOT_FOUND' using errcode = 'P0002';
    end if;
  else
    raise exception 'INVALID_TARGET' using errcode = '22023';
  end if;

  if follow then
    insert into public.follows (user_id, target_type, target_id)
    values (auth.uid(), kind, target)
    on conflict (user_id, target_type, target_id) do nothing;
  else
    delete from public.follows as f
    where f.user_id = auth.uid() and f.target_type = kind and f.target_id = target;
  end if;

  return follow;
end;
$$;

REVOKE EXECUTE ON FUNCTION public.set_follow(text, text, BOOLEAN) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.set_follow(text, text, BOOLEAN) TO authenticated;

-- The new type. Its row is one batched notification per follow per day, and its payload has the
-- name, how many activities so far today, and where it opens.
ALTER TABLE public.notifications DROP CONSTRAINT notifications_type_check;
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
      'new_activity'
    )
  );

ALTER TABLE public.notification_preferences DROP CONSTRAINT notification_preferences_type_check;
ALTER TABLE public.notification_preferences
ADD CONSTRAINT notification_preferences_type_check
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
      'new_activity'
    )
  );

-- Tells a category's or group's followers about a new activity, once a day per follow. The count
-- is today's activities there, so the payload is always the day's total.
CREATE FUNCTION private.notify_followers_of_new_activity()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
declare
  day_start timestamptz := date_trunc('day', now() at time zone 'America/Boise') at time zone 'America/Boise';
  day_key text := to_char(now() at time zone 'America/Boise', 'YYYY-MM-DD');
  label text;
  slug text;
  total integer;
  people uuid[];
begin
  if new.status <> 'published' then
    return new;
  end if;

  if new.visibility = 'members' then
    select c.name into label from public.categories as c where c.id = new.category_id;

    select count(*)::integer into total
    from public.activities as a
    where
      a.category_id = new.category_id
      and a.visibility = 'members'
      and a.status = 'published'
      and a.created_at >= day_start;

    select coalesce(array_agg(f.user_id), '{}') into people
    from public.follows as f
    join public.profiles as p on p.id = f.user_id
    where
      f.target_type = 'category'
      and f.target_id = new.category_id
      and p.status = 'active'
      and f.user_id <> new.organizer_id;

    if cardinality(people) > 0 then
      perform private.notify(
        people,
        'new_activity',
        null,
        jsonb_build_object(
          'name', label,
          'count', total,
          'href', '/discover?cat=' || new.category_id
        ),
        'new_activity:category:' || new.category_id || ':' || day_key
      );
    end if;
  end if;

  if new.group_id is not null then
    select g.name, g.slug into label, slug from public.groups as g where g.id = new.group_id;

    select count(*)::integer into total
    from public.activities as a
    where
      a.group_id = new.group_id
      and a.status = 'published'
      and a.created_at >= day_start;

    -- Only the group's active members hear about its activities.
    select coalesce(array_agg(f.user_id), '{}') into people
    from public.follows as f
    join public.profiles as p on p.id = f.user_id
    join public.group_members as m on m.user_id = f.user_id and m.group_id = new.group_id
    where
      f.target_type = 'group'
      and f.target_id = new.group_id::text
      and p.status = 'active'
      and m.status = 'active'
      and f.user_id <> new.organizer_id;

    if cardinality(people) > 0 then
      perform private.notify(
        people,
        'new_activity',
        null,
        jsonb_build_object(
          'name', label,
          'count', total,
          'href', '/groups/' || slug
        ),
        'new_activity:group:' || new.group_id || ':' || day_key
      );
    end if;
  end if;

  return new;
end;
$$;

CREATE TRIGGER notify_followers_of_new_activity
AFTER INSERT ON public.activities
FOR EACH ROW
EXECUTE FUNCTION private.notify_followers_of_new_activity();
