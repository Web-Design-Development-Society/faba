-- Curated tags (SRCH-03). Design document sections 10.3 and 10.5, and FR-CAT-3 and FR-CAT-5. An
-- activity has 0 to 3 tags from a short list that admins keep, such as Free and Family-friendly, and
-- More filters filters by them. Free-form tags aren't supported (WH-08).
CREATE TABLE public.tags (
  id text PRIMARY KEY CHECK (id ~ '^[a-z][a-z0-9-]*$'),
  name text NOT NULL CHECK (char_length(name) BETWEEN 1 AND 40),
  sort_order INTEGER NOT NULL,
  is_active BOOLEAN NOT NULL DEFAULT TRUE,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now()
);

CREATE TRIGGER tags_set_updated_at
BEFORE UPDATE ON public.tags
FOR EACH ROW
EXECUTE FUNCTION private.set_updated_at();

ALTER TABLE public.tags ENABLE ROW LEVEL SECURITY;

CREATE POLICY "Active members read tags" ON public.tags
FOR SELECT
TO authenticated
USING ((SELECT private.is_active_member()));

-- The list in FR-CAT-3. Admins change it in the dashboard until the Phase 3 admin screens.
INSERT INTO public.tags
  (id, name, sort_order)
VALUES
  ('free', 'Free', 1),
  ('family-friendly', 'Family-friendly', 2),
  ('beginner-friendly', 'Beginner-friendly', 3),
  ('accessible', 'Accessible', 4);

CREATE TABLE public.activity_tags (
  activity_id uuid NOT NULL REFERENCES public.activities (id)
    ON DELETE CASCADE,
  tag_id text NOT NULL REFERENCES public.tags (id),
  PRIMARY KEY (activity_id, tag_id)
);

CREATE INDEX activity_tags_tag_idx ON public.activity_tags (tag_id, activity_id);

ALTER TABLE public.activity_tags ENABLE ROW LEVEL SECURITY;

-- Members read the tags of the activities they can read. Writes go through set_activity_tags().
CREATE POLICY "Members read the tags of activities they can read" ON public.activity_tags
FOR SELECT
TO authenticated
USING (EXISTS (SELECT FROM public.activities AS a WHERE a.id = activity_id));

-- Sets an activity's tags to `tag_ids`, replacing the ones it had. Only its organizer can, with up
-- to 3 tags that are offered, and only until it starts, like the rest of update_activity()'s
-- fields. An activity keeps a tag that's no longer offered until it's taken off, as with categories.
CREATE FUNCTION public.set_activity_tags(activity_id uuid, tag_ids text[])
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
declare
  activity public.activities;
  wanted text[] := array(select distinct unnest(coalesce(set_activity_tags.tag_ids, '{}')));
  had text[];
begin
  if not private.is_active_member() then
    raise exception 'NOT_ACTIVE' using errcode = '42501';
  end if;

  select * into activity
  from public.activities as a
  where a.id = set_activity_tags.activity_id
  for update;

  -- The same for an activity that doesn't exist, so nobody learns which ones do.
  if not found or activity.organizer_id is distinct from auth.uid() then
    raise exception 'NOT_ORGANIZER' using errcode = '42501';
  end if;

  had := array(
    select t.tag_id from public.activity_tags as t where t.activity_id = activity.id
  );

  if wanted <@ had and had <@ wanted then
    return;
  end if;

  if activity.starts_at <= now() then
    raise exception 'ACTIVITY_STARTED' using errcode = '22023';
  end if;

  if cardinality(wanted) > 3 then
    raise exception 'TOO_MANY_TAGS' using errcode = '22023';
  end if;

  if exists (
    select from unnest(wanted) as w (id)
    where w.id <> all(had) and not exists (
      select from public.tags as g where g.id = w.id and g.is_active
    )
  ) then
    raise exception 'INVALID_TAG' using errcode = '22023';
  end if;

  delete from public.activity_tags as t
  where t.activity_id = activity.id and t.tag_id <> all(wanted);

  insert into public.activity_tags (activity_id, tag_id)
  select activity.id, w.id
  from unnest(wanted) as w (id)
  on conflict do nothing;
end;
$$;

GRANT EXECUTE ON FUNCTION public.set_activity_tags(uuid, text[]) TO authenticated;
