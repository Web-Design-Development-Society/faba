-- Foundation for every later migration: the private schema, extensions, and the updated_at trigger.
-- Design document sections 10.1 and 9.8.
-- The private schema holds helper functions, the audit log, and job internals.
-- It is not exposed through the Data API.
CREATE SCHEMA IF NOT EXISTS private;

REVOKE ALL ON SCHEMA private FROM PUBLIC, anon, authenticated;

CREATE EXTENSION IF NOT EXISTS citext WITH SCHEMA extensions;

-- Keeps updated_at current on every mutable table.
CREATE FUNCTION private.set_updated_at()
RETURNS trigger
LANGUAGE plpgsql
SET search_path = ''
AS $$
begin
  new.updated_at := now();
  return new;
end;
$$;
