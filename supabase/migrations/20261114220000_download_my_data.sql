-- Downloading my data (PRIV-01). `export_my_data()` returns everything FABA holds about the signed-in
-- member, as one JSON document: their profile, RSVPs, the activities they organize, their group and
-- league memberships and sign-ups, and their notifications. Each query filters by the caller, so the
-- export holds only their own data. Exports are rate-limited: three in 24 hours.

CREATE TABLE public.data_exports (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id uuid NOT NULL REFERENCES public.profiles (id)
    ON DELETE CASCADE,
  created_at timestamptz NOT NULL DEFAULT now()
);

CREATE INDEX data_exports_user_idx ON public.data_exports (user_id, created_at);

ALTER TABLE public.data_exports ENABLE ROW LEVEL SECURITY;

CREATE FUNCTION public.export_my_data()
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
declare
  me uuid := auth.uid();
  recent INTEGER;
begin
  if me is null then
    raise exception 'NOT_SIGNED_IN' using errcode = '42501';
  end if;

  select count(*)::INTEGER into recent
  from public.data_exports as e
  where e.user_id = me and e.created_at > now() - interval '24 hours';

  if recent >= 3 then
    raise exception 'EXPORT_QUOTA_EXCEEDED' using errcode = '53400';
  end if;

  insert into public.data_exports (user_id) values (me);

  return jsonb_build_object(
    'exported_at', now(),
    'profile', (select to_jsonb(p) from public.profiles as p where p.id = me),
    'rsvps', coalesce((select jsonb_agg(to_jsonb(r)) from public.rsvps as r where r.user_id = me), '[]'::jsonb),
    'organized_activities', coalesce((select jsonb_agg(to_jsonb(a)) from public.activities as a where a.organizer_id = me), '[]'::jsonb),
    'group_memberships', coalesce((select jsonb_agg(to_jsonb(m)) from public.group_members as m where m.user_id = me), '[]'::jsonb),
    'league_registrations', coalesce((select jsonb_agg(to_jsonb(l)) from public.league_registrations as l where l.user_id = me), '[]'::jsonb),
    'notifications', coalesce((select jsonb_agg(to_jsonb(n)) from public.notifications as n where n.recipient_id = me), '[]'::jsonb)
  );
end;
$$;

REVOKE EXECUTE ON FUNCTION public.export_my_data() FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.export_my_data() TO authenticated;
