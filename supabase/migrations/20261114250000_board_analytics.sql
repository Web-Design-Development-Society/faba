-- Board analytics (ANLY-01). Each night, `private.compute_daily_metrics(day)` writes the day's
-- aggregates into `daily_metrics`: weekly active members, new members, activities by category, RSVPs,
-- the self-reported full-time and part-time split, and the number of organizers. A group smaller
-- than 10 is never stored, so no row can point at a few people. Only moderators can read the table.

CREATE TABLE public.daily_metrics (
  day date NOT NULL,
  metric text NOT NULL CHECK (
    metric IN (
      'weekly_active_members',
      'new_members',
      'activities',
      'rsvps',
      'faculty_full_time',
      'faculty_part_time',
      'organizers'
    )
  ),
  -- The category for activities, and blank for the rest.
  dimension text NOT NULL DEFAULT '',
  value INTEGER NOT NULL CHECK (value >= 10),
  PRIMARY KEY (day, metric, dimension)
);

ALTER TABLE public.daily_metrics ENABLE ROW LEVEL SECURITY;

CREATE POLICY "Moderators read the board's metrics" ON public.daily_metrics
FOR SELECT
TO authenticated
USING (private.is_moderator());

-- Computes one day's metrics. Returns how many rows it stored.
CREATE FUNCTION private.compute_daily_metrics(day date)
RETURNS INTEGER
LANGUAGE plpgsql
SET search_path = ''
AS $$
declare
  window_start timestamptz := (compute_daily_metrics.day::timestamp - interval '6 days') AT TIME ZONE 'America/Boise';
  day_start timestamptz := (compute_daily_metrics.day::timestamp) AT TIME ZONE 'America/Boise';
  day_end timestamptz := ((compute_daily_metrics.day + 1)::timestamp) AT TIME ZONE 'America/Boise';
  stored INTEGER := 0;
  n INTEGER;
  cat record;
begin
  -- Weekly active members: anyone who RSVPed or posted an activity in the seven days to `day`.
  select count(*)::INTEGER into n from (
    select r.user_id from public.rsvps as r where r.created_at >= window_start and r.created_at < day_end
    union
    select a.organizer_id from public.activities as a where a.created_at >= window_start and a.created_at < day_end and a.organizer_id is not null
  ) as active;
  if n >= 10 then
    insert into public.daily_metrics (day, metric, dimension, value) values (compute_daily_metrics.day, 'weekly_active_members', '', n)
    on conflict on constraint daily_metrics_pkey do update set value = excluded.value;
    stored := stored + 1;
  end if;

  select count(*)::INTEGER into n from public.profiles as p
  where p.created_at >= day_start and p.created_at < day_end;
  if n >= 10 then
    insert into public.daily_metrics (day, metric, dimension, value) values (compute_daily_metrics.day, 'new_members', '', n)
    on conflict on constraint daily_metrics_pkey do update set value = excluded.value;
    stored := stored + 1;
  end if;

  -- Activities by category, each category on its own.
  for cat in
    select count(*)::INTEGER as total, a.category_id as category
    from public.activities as a
    where a.created_at >= day_start and a.created_at < day_end
    group by a.category_id
  loop
    if cat.total >= 10 then
      insert into public.daily_metrics (day, metric, dimension, value) values (compute_daily_metrics.day, 'activities', cat.category, cat.total)
      on conflict on constraint daily_metrics_pkey do update set value = excluded.value;
      stored := stored + 1;
    end if;
  end loop;

  select count(*)::INTEGER into n from public.rsvps as r where r.created_at >= day_start and r.created_at < day_end;
  if n >= 10 then
    insert into public.daily_metrics (day, metric, dimension, value) values (compute_daily_metrics.day, 'rsvps', '', n)
    on conflict on constraint daily_metrics_pkey do update set value = excluded.value;
    stored := stored + 1;
  end if;

  -- The self-reported split. Prefer not to say counts toward neither.
  select count(*)::INTEGER into n from public.profile_private as pp where pp.faculty_type = 'full_time';
  if n >= 10 then
    insert into public.daily_metrics (day, metric, dimension, value) values (compute_daily_metrics.day, 'faculty_full_time', '', n)
    on conflict on constraint daily_metrics_pkey do update set value = excluded.value;
    stored := stored + 1;
  end if;
  select count(*)::INTEGER into n from public.profile_private as pp where pp.faculty_type = 'part_time';
  if n >= 10 then
    insert into public.daily_metrics (day, metric, dimension, value) values (compute_daily_metrics.day, 'faculty_part_time', '', n)
    on conflict on constraint daily_metrics_pkey do update set value = excluded.value;
    stored := stored + 1;
  end if;

  -- Organizers who posted an activity in the seven days to `day`.
  select count(distinct a.organizer_id)::INTEGER into n from public.activities as a
  where a.created_at >= window_start and a.created_at < day_end and a.organizer_id is not null;
  if n >= 10 then
    insert into public.daily_metrics (day, metric, dimension, value) values (compute_daily_metrics.day, 'organizers', '', n)
    on conflict on constraint daily_metrics_pkey do update set value = excluded.value;
    stored := stored + 1;
  end if;

  return stored;
end;
$$;

REVOKE EXECUTE
ON FUNCTION private.compute_daily_metrics(date)
FROM PUBLIC, anon, authenticated, service_role;

-- Yesterday's metrics, computed at 11:15 UTC, which is 5:15 AM in Rexburg.
SELECT cron.schedule(
  'compute-daily-metrics',
  '15 11 * * *',
  'select private.compute_daily_metrics(current_date - 1)'
);
