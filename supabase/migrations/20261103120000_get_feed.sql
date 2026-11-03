-- The Home feed (ACT-01). Design document sections 7.4, 9.6 and 10.5.

-- With id in the index, each page starts right at its cursor.
DROP INDEX public.activities_feed_idx;

CREATE INDEX activities_feed_idx ON public.activities (starts_at, id)
WHERE status = 'published' AND hidden_at IS NULL;

-- Upcoming activities, soonest first, including ones that started in the last 3 hours. A page
-- starts after the cursor, the start time and id of the previous page's last activity. Cancelled
-- and hidden activities aren't in the feed, even for their organizer. It runs as the caller, so
-- Row Level Security applies.
CREATE FUNCTION public.get_feed(
  after_starts_at timestamptz DEFAULT NULL,
  after_id uuid DEFAULT NULL,
  page_size INTEGER DEFAULT 20
)
RETURNS SETOF public.activities
LANGUAGE sql
STABLE
SET search_path = ''
AS $$
  SELECT *
  FROM public.activities
  WHERE
    status = 'published'
    AND hidden_at IS NULL
    AND starts_at >= now() - INTERVAL '3 hours'
    AND (after_starts_at IS NULL OR (starts_at, id) > (after_starts_at, after_id))
  ORDER BY starts_at, id
  LIMIT least(page_size, 50);
$$;

GRANT EXECUTE ON FUNCTION public.get_feed(timestamptz, uuid, INTEGER) TO authenticated;

-- The signed-in member's RSVP to an activity: going, not_going, or NULL. PostgREST reads it as a
-- computed field, `my_rsvp`, on activities and on get_feed()'s rows, because it can't filter
-- RSVPs embedded in a function's rows by user_id.
CREATE FUNCTION public.my_rsvp(activity public.activities)
RETURNS text
LANGUAGE sql
STABLE
SET search_path = ''
AS $$
  SELECT status
  FROM public.rsvps
  WHERE activity_id = activity.id AND user_id = auth.uid();
$$;

GRANT EXECUTE ON FUNCTION public.my_rsvp(public.activities) TO authenticated;
