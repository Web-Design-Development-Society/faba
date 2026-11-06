-- Searching activities by keyword (SRCH-01). Design document sections 7.10 and 10.3, and FR-SRCH-2.
-- Postgres full-text search, with English stemming, over the title, place and description, and the
-- organizer's display name. Private details (ACT-09) will never be in it.

-- What search reads, kept up to date by Postgres: the title first, then the place, then the
-- description.
ALTER TABLE public.activities
ADD COLUMN search_doc tsvector GENERATED ALWAYS AS (
  setweight(to_tsvector('english', title), 'A') || setweight(
    to_tsvector('english', location_name),
    'B'
  ) || setweight(to_tsvector('english', coalesce(description, '')), 'C')
) STORED;

CREATE INDEX activities_search_idx ON public.activities USING gin (search_doc);

-- Activities matching `q`, as cards read them. Every word must match, in the activity or its
-- organizer's name, so "hike Hana" finds Hana's hikes. The last word matches as a prefix, so
-- "pickle" finds "pickleball" while someone types. Like get_feed(), it leaves out
-- cancelled and hidden ones, and by default, ones that are over: upcoming ones come soonest first.
-- With `include_past`, past ones come too, newest first. The cursor is the last result's start time
-- and id. It runs as the caller, so Row Level Security applies, and an organizer members can't read
-- doesn't match.
CREATE FUNCTION public.search_activities(
  q text,
  include_past BOOLEAN DEFAULT FALSE,
  after_starts_at timestamptz DEFAULT NULL,
  after_id uuid DEFAULT NULL,
  page_size INTEGER DEFAULT 20
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
          string_agg(
            word || CASE
              WHEN n = last THEN ':*'
              ELSE ''
            END,
            ' & '
            ORDER BY n
          )
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
    AND (a.search_doc || to_tsvector('english', coalesce(p.display_name, ''))) @@ query.terms
    AND (
      after_starts_at IS NULL
      OR (NOT include_past AND (a.starts_at, a.id) > (after_starts_at, after_id))
      OR (include_past AND (a.starts_at, a.id) < (after_starts_at, after_id))
    )
  ORDER BY
    CASE
      WHEN NOT include_past THEN a.starts_at
    END,
    CASE
      WHEN NOT include_past THEN a.id
    END,
    CASE
      WHEN include_past THEN a.starts_at
    END DESC,
    CASE
      WHEN include_past THEN a.id
    END DESC
  LIMIT least(page_size, 50);
$$;

GRANT EXECUTE
ON FUNCTION public.search_activities(text, BOOLEAN, timestamptz, uuid, INTEGER)
TO authenticated;
