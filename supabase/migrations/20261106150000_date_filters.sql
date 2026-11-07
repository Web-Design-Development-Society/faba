-- Date filters (SRCH-02). Design document sections 7.10 and 10.5, and FR-SRCH-3. Today, This week,
-- This weekend and a custom range are ranges of start times, which the app works out in Rexburg
-- time (src/lib/time.ts), so the feed and search take a range. They combine with the category and
-- the search words.

-- The feed as before (20261104140000_feed_by_category.sql), starting at or after `starts_from`
-- and before `starts_before`, when given.
DROP FUNCTION public.get_feed(timestamptz, uuid, INTEGER, text);

CREATE FUNCTION public.get_feed(
  after_starts_at timestamptz DEFAULT NULL,
  after_id uuid DEFAULT NULL,
  page_size INTEGER DEFAULT 20,
  category text DEFAULT NULL,
  starts_from timestamptz DEFAULT NULL,
  starts_before timestamptz DEFAULT NULL
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
    AND (starts_from IS NULL OR starts_at >= starts_from)
    AND (starts_before IS NULL OR starts_at < starts_before)
  ORDER BY starts_at, id
  LIMIT least(page_size, 50);
$$;

GRANT EXECUTE
ON FUNCTION public.get_feed(timestamptz, uuid, INTEGER, text, timestamptz, timestamptz)
TO authenticated;

-- Search as before (20261106140000_search_activities.sql), with the same range, and a category,
-- since search results have the same chips as the feed.
DROP FUNCTION public.search_activities(text, BOOLEAN, timestamptz, uuid, INTEGER);

CREATE FUNCTION public.search_activities(
  q text,
  include_past BOOLEAN DEFAULT FALSE,
  after_starts_at timestamptz DEFAULT NULL,
  after_id uuid DEFAULT NULL,
  page_size INTEGER DEFAULT 20,
  starts_from timestamptz DEFAULT NULL,
  starts_before timestamptz DEFAULT NULL,
  category text DEFAULT NULL
)
RETURNS SETOF public.activities
LANGUAGE sql
STABLE
SET search_path = ''
AS $$
  WITH
    words AS (
      SELECT word, n, max(n) OVER () AS last
      FROM regexp_split_to_table(lower(left(q, 100)), '[^[:alnum:]]+') WITH ORDINALITY AS w (
        word,
        n
      )
      WHERE word != ''
    ),
    -- Built once, and nothing when there are no words or only common ones, such as "the".
    query AS MATERIALIZED (
      SELECT terms
      FROM (
        SELECT to_tsquery(
          'english',
          string_agg(word || CASE WHEN n = last THEN ':*' ELSE '' END, ' & ' ORDER BY n)
        ) AS terms
        FROM words
      ) AS t
      WHERE numnode(terms) > 0
    )
  SELECT a.*
  FROM public.activities AS a
  CROSS JOIN query
  LEFT JOIN public.profiles AS p ON p.id = a.organizer_id
  WHERE
    a.status = 'published'
    AND a.hidden_at IS NULL
    AND (include_past OR a.starts_at >= now() - INTERVAL '3 hours')
    AND (category IS NULL OR a.category_id = category)
    AND (starts_from IS NULL OR a.starts_at >= starts_from)
    AND (starts_before IS NULL OR a.starts_at < starts_before)
    AND (a.search_doc || to_tsvector('english', coalesce(p.display_name, ''))) @@ query.terms
    AND (
      after_starts_at IS NULL
      OR (NOT include_past AND (a.starts_at, a.id) > (after_starts_at, after_id))
      OR (include_past AND (a.starts_at, a.id) < (after_starts_at, after_id))
    )
  ORDER BY
    CASE WHEN NOT include_past THEN a.starts_at END,
    CASE WHEN NOT include_past THEN a.id END,
    CASE WHEN include_past THEN a.starts_at END DESC,
    CASE WHEN include_past THEN a.id END DESC
  LIMIT least(page_size, 50);
$$;

GRANT EXECUTE
ON FUNCTION public.search_activities(
  text,
  BOOLEAN,
  timestamptz,
  uuid,
  INTEGER,
  timestamptz,
  timestamptz,
  text
)
TO authenticated;
