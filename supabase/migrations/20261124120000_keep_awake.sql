-- Keeping a free database awake (OPS-05, ADR-019). Supabase pauses a free project after 7 days
-- without activity. Once a day, the Worker's Cron Trigger calls this through the Data API with the
-- publishable key, a real query that reads and writes nothing. Anyone with the publishable key can
-- call it, which costs nothing.
CREATE FUNCTION public.keep_awake()
RETURNS BOOLEAN
LANGUAGE sql
STABLE
SET search_path = ''
AS $$
  SELECT TRUE;
$$;

REVOKE EXECUTE ON FUNCTION public.keep_awake() FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.keep_awake() TO anon, authenticated;
