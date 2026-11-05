-- Discover's category chips (ACT-06). Design document sections 7.10 and 10.5.

-- Each category's page starts right at its cursor too.
CREATE INDEX activities_feed_category_idx ON public.activities (category_id, starts_at, id)
WHERE status = 'published' AND hidden_at IS NULL;

-- Upcoming activities, soonest first, as before (20261103120000_get_feed.sql). Given a category,
-- only its activities. The category filters before the limit, so a page holds page_size of them.
-- It runs as the caller, so Row Level Security applies.
DROP FUNCTION public.get_feed(timestamptz, uuid, INTEGER);

CREATE FUNCTION public.get_feed(
  after_starts_at timestamptz DEFAULT NULL,
  after_id uuid DEFAULT NULL,
  page_size INTEGER DEFAULT 20,
  category text DEFAULT NULL
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
    AND (category IS NULL OR category_id = category)
  ORDER BY starts_at, id
  LIMIT least(page_size, 50);
$$;

GRANT EXECUTE ON FUNCTION public.get_feed(timestamptz, uuid, INTEGER, text) TO authenticated;
