-- More filters (SRCH-03). Design document sections 7.10 and 10.5, and FR-SRCH-4. The feed and
-- search can keep to activities with spots left (RSVP-04), and to ones with every tag asked for,
-- such as Free and Family-friendly. A tag that isn't offered is left out, as the app leaves it out
-- of More filters. These combine with the other filters.

-- The feed as before (20261106150000_date_filters.sql), with the new filters.
DROP FUNCTION public.get_feed(timestamptz, uuid, INTEGER, text, timestamptz, timestamptz);

CREATE FUNCTION public.get_feed(
  after_starts_at timestamptz DEFAULT NULL,
  after_id uuid DEFAULT NULL,
  page_size INTEGER DEFAULT 20,
  category text DEFAULT NULL,
  starts_from timestamptz DEFAULT NULL,
  starts_before timestamptz DEFAULT NULL,
  has_spots BOOLEAN DEFAULT FALSE,
  tag_ids text[] DEFAULT NULL
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
    AND (NOT has_spots OR capacity IS NULL OR going_count + guest_total < capacity)
    AND NOT EXISTS (
      SELECT
      FROM unnest(tag_ids) AS t (id)
      JOIN public.tags AS g ON g.id = t.id AND g.is_active
      WHERE
        NOT EXISTS (
          SELECT
          FROM public.activity_tags AS at
          WHERE at.activity_id = activities.id AND at.tag_id = t.id
        )
    )
  ORDER BY starts_at, id
  LIMIT least(page_size, 50);
$$;

GRANT EXECUTE
ON FUNCTION public.get_feed(
  timestamptz,
  uuid,
  INTEGER,
  text,
  timestamptz,
  timestamptz,
  BOOLEAN,
  text[]
)
TO authenticated;

-- Search as before (20261106150000_date_filters.sql), with the new filters.
DROP FUNCTION public.search_activities(
  text,
  BOOLEAN,
  timestamptz,
  uuid,
  INTEGER,
  timestamptz,
  timestamptz,
  text
);

CREATE FUNCTION public.search_activities(
  q text,
  include_past BOOLEAN DEFAULT FALSE,
  after_starts_at timestamptz DEFAULT NULL,
  after_id uuid DEFAULT NULL,
  page_size INTEGER DEFAULT 20,
  starts_from timestamptz DEFAULT NULL,
  starts_before timestamptz DEFAULT NULL,
  category text DEFAULT NULL,
  has_spots BOOLEAN DEFAULT FALSE,
  tag_ids text[] DEFAULT NULL
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
    AND (NOT has_spots OR a.capacity IS NULL OR a.going_count + a.guest_total < a.capacity)
    AND NOT EXISTS (
      SELECT
      FROM unnest(tag_ids) AS t (id)
      JOIN public.tags AS g ON g.id = t.id AND g.is_active
      WHERE
        NOT EXISTS (
          SELECT
          FROM public.activity_tags AS at
          WHERE at.activity_id = a.id AND at.tag_id = t.id
        )
    )
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
  text,
  BOOLEAN,
  text[]
)
TO authenticated;
