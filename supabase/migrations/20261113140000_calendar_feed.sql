-- A personal calendar feed (CAL-01). Design document section 6.6 Phase 3 and section 8.13. A member
-- gets a secret link that serves an iCal feed of the activities they're going to. The token is a
-- credential, so it's random, shown once, and stored only as a SHA-256 hash. Resetting makes a new
-- one, and the old link stops working. Calendar apps don't sign in, so the feed reads through
-- calendar_feed_events(), which checks the hash, and rate-limits each feed.

-- One feed per member. Only the hash is stored, so the link itself is never in the database.
CREATE TABLE public.calendar_feeds (
  user_id uuid PRIMARY KEY REFERENCES public.profiles (id)
    ON DELETE CASCADE,
  token_hash text NOT NULL UNIQUE,
  created_at timestamptz NOT NULL DEFAULT now()
);

ALTER TABLE public.calendar_feeds ENABLE ROW LEVEL SECURITY;

-- Members see whether they have a feed. The hash is useless without the token.
CREATE POLICY calendar_feeds_select_own ON public.calendar_feeds
FOR SELECT
TO authenticated
USING (user_id = (SELECT auth.uid()));

GRANT SELECT ON public.calendar_feeds TO authenticated;

-- Requests to each feed, counted by the hour, for the rate limit. No one reads or writes it
-- directly, so it has no policies and no grants.
CREATE TABLE public.calendar_feed_requests (
  user_id uuid NOT NULL REFERENCES public.profiles (id)
    ON DELETE CASCADE,
  hour timestamptz NOT NULL,
  requests INTEGER NOT NULL DEFAULT 0,
  PRIMARY KEY (user_id, hour)
);

ALTER TABLE public.calendar_feed_requests ENABLE ROW LEVEL SECURITY;

-- Makes `token_hash` the signed-in member's feed, replacing any earlier one. An active member only.
CREATE FUNCTION public.reset_calendar_feed(token_hash text)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
begin
  if not private.is_active_member() then
    raise exception 'NOT_ACTIVE' using errcode = '42501';
  end if;

  insert into public.calendar_feeds as f (user_id, token_hash)
  values ((select auth.uid()), reset_calendar_feed.token_hash)
  on conflict (user_id) do update
  set token_hash = excluded.token_hash, created_at = now();
end;
$$;

GRANT EXECUTE ON FUNCTION public.reset_calendar_feed(text) TO authenticated;

-- The going activities for the feed whose token hashes to `token_hash`, for the iCal feed. A member
-- who's no longer active gets nothing. Each feed can make 60 requests an hour, then gets an error.
-- Activities from the last 30 days on are included, so changes and cancellations reach calendars.
-- Details for attendees are left out, since the link is a credential that anyone can hold.
CREATE FUNCTION public.calendar_feed_events(token_hash text)
RETURNS TABLE (
  id uuid,
  title text,
  starts_at timestamptz,
  ends_at timestamptz,
  location_name text,
  description text,
  status text,
  version INTEGER
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
declare
  owner uuid;
  requests_this_hour integer;
begin
  select f.user_id into owner
  from public.calendar_feeds as f
  where f.token_hash = calendar_feed_events.token_hash;

  if not found then
    raise exception 'FEED_NOT_FOUND' using errcode = 'P0002';
  end if;

  insert into public.calendar_feed_requests as r (user_id, hour, requests)
  values (owner, date_trunc('hour', now()), 1)
  on conflict (user_id, hour) do update set requests = r.requests + 1
  returning r.requests into requests_this_hour;

  if requests_this_hour > 60 then
    raise exception 'FEED_RATE_LIMITED' using errcode = '53400';
  end if;

  if not exists (
    select from public.profiles as p where p.id = owner and p.status = 'active'
  ) then
    raise exception 'FEED_NOT_FOUND' using errcode = 'P0002';
  end if;

  return query
    select a.id, a.title, a.starts_at, a.ends_at, a.location_name, a.description, a.status, a.version
    from public.rsvps as r
    join public.activities as a on a.id = r.activity_id
    where
      r.user_id = owner
      and r.status = 'going'
      and a.hidden_at is null
      and a.starts_at >= now() - interval '30 days'
      and (
        a.visibility = 'members'
        or exists (
          select from public.group_members as m
          where m.group_id = a.group_id and m.user_id = owner and m.status = 'active'
        )
      )
    order by a.starts_at, a.id;
end;
$$;

GRANT EXECUTE ON FUNCTION public.calendar_feed_events(text) TO anon, authenticated;
