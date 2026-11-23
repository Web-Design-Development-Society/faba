-- A picture when posting (MEDIA-02). New activity can save a picture as the activity's cover, and a
-- repeating series (REC-01) shows it on every date: the dates it makes when it's posted, and the
-- ones it adds later as it rolls on. The dates share the one picture, which belongs to the first
-- date (images.activity_id). A date given its own cover from its page keeps that one.

-- The series' picture, which the dates it adds later get.
ALTER TABLE public.activity_series
ADD COLUMN cover_image_id uuid REFERENCES public.images (id)
  ON DELETE SET NULL;

CREATE INDEX activity_series_cover_image_idx ON public.activity_series (cover_image_id);

-- Gives the series of `activity_id` that date's cover: the series keeps it for the dates it adds
-- later, and its other dates with no cover of their own get it now. Its organizer or a
-- co-organizer can, as for set_activity_cover(). Returns how many other dates got it.
CREATE FUNCTION public.share_cover_with_series(activity_id uuid)
RETURNS INTEGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
declare
  activity public.activities;
  shared integer;
begin
  if not private.is_active_member() then
    raise exception 'NOT_ACTIVE' using errcode = '42501';
  end if;

  select * into activity
  from public.activities as a
  where a.id = share_cover_with_series.activity_id and a.hidden_at is null
  for update;

  if not found then
    raise exception 'ACTIVITY_NOT_FOUND' using errcode = 'P0002';
  end if;

  if activity.organizer_id is distinct from auth.uid() and not exists (
    select from public.activity_co_organizers as c
    where c.activity_id = activity.id and c.user_id = auth.uid()
  ) then
    raise exception 'NOT_ORGANIZER' using errcode = '42501';
  end if;

  if activity.series_id is null or activity.cover_image_id is null then
    return 0;
  end if;

  update public.activity_series as s
  set cover_image_id = activity.cover_image_id
  where s.id = activity.series_id;

  update public.activities as a
  set cover_image_id = activity.cover_image_id
  where a.series_id = activity.series_id and a.id <> activity.id and a.cover_image_id is null;
  get diagnostics shared = row_count;
  return shared;
end;
$$;

REVOKE EXECUTE ON FUNCTION public.share_cover_with_series(uuid) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.share_cover_with_series(uuid) TO authenticated;

-- The same as before (20261112120000_recurring_activities.sql, REC-01), with the series' cover on
-- each date it adds.
CREATE OR REPLACE FUNCTION private.generate_occurrences(
  series_id uuid,
  as_of timestamptz DEFAULT now()
)
RETURNS INTEGER
LANGUAGE plpgsql
SET search_path = ''
AS $$
declare
  s public.activity_series;
  through date;
  details text;
  d date;
  starts timestamptz;
  new_id uuid;
  made integer := 0;
begin
  select * into s
  from public.activity_series as x
  where x.id = generate_occurrences.series_id
  for update;

  if not found then
    return 0;
  end if;

  through := least((as_of at time zone s.timezone)::date + 56, s.until_date);

  if through <= s.generated_through then
    return 0;
  end if;

  select p.details into details
  from private.series_private_details as p
  where p.series_id = s.id;

  for d in
    select x.d from private.series_dates(s, through) as x (d) where x.d > s.generated_through
  loop
    -- The wall clock on that date, in the series' time zone, whatever the offset is then.
    starts := (d + s.start_time) at time zone s.timezone;

    continue when starts <= as_of;

    insert into public.activities (
      organizer_id,
      category_id,
      title,
      description,
      starts_at,
      ends_at,
      timezone,
      location_name,
      cost_note,
      going_count,
      capacity,
      guests_allowed,
      max_guests_per_rsvp,
      group_id,
      visibility,
      series_id,
      cover_image_id
    )
    values (
      s.organizer_id,
      s.category_id,
      s.title,
      s.description,
      starts,
      starts + s.duration,
      s.timezone,
      s.location_name,
      s.cost_note,
      1,
      s.capacity,
      s.guests_allowed,
      s.max_guests_per_rsvp,
      s.group_id,
      s.visibility,
      s.id,
      s.cover_image_id
    )
    returning id into new_id;

    insert into public.rsvps (activity_id, user_id, status)
    values (new_id, s.organizer_id, 'going');

    insert into public.activity_tags (activity_id, tag_id)
    select new_id, t.id
    from unnest(s.tag_ids) as t (id);

    perform private.set_private_details(new_id, details);

    made := made + 1;
  end loop;

  update public.activity_series as x
  set generated_through = through
  where x.id = s.id;

  return made;
end;
$$;
