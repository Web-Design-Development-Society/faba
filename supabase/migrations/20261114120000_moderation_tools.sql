-- Moderation and admin tools (MOD-08). Design document sections 7.11, 9.12 and 10.3. Groups can be
-- reported, moderators keep notes on what's reported, every new report tells the moderators, admins
-- manage categories, tags and roles, and admins can read the audit log by actor and target.

-- Groups can be reported, like profiles, activities and updates.
ALTER TABLE public.reports DROP CONSTRAINT reports_target_type_check;
ALTER TABLE public.reports
ADD CONSTRAINT reports_target_type_check
  CHECK (target_type IN ('activity', 'profile', 'activity_update', 'group'));

-- The notification type for a new report, for the moderators.
ALTER TABLE public.notifications DROP CONSTRAINT notifications_type_check;
ALTER TABLE public.notifications
ADD CONSTRAINT notifications_type_check
  CHECK (
    type IN (
      'activity_changed',
      'activity_cancelled',
      'activity_restored',
      'organizer_update',
      'rsvp_confirmed',
      'new_attendees',
      'reminder',
      'board_announcement',
      'group_join_request',
      'group_update',
      'group_join_approved',
      'group_owner',
      'rsvp_promoted',
      'rsvp_removed',
      'new_activity',
      'report_received'
    )
  );

ALTER TABLE public.notification_preferences DROP CONSTRAINT notification_preferences_type_check;
ALTER TABLE public.notification_preferences
ADD CONSTRAINT notification_preferences_type_check
  CHECK (
    type IN (
      'activity_changed',
      'activity_cancelled',
      'activity_restored',
      'organizer_update',
      'rsvp_confirmed',
      'new_attendees',
      'reminder',
      'board_announcement',
      'group_join_request',
      'group_update',
      'group_join_approved',
      'group_owner',
      'rsvp_promoted',
      'rsvp_removed',
      'new_activity',
      'report_received'
    )
  );

-- Whether the signed-in member is an admin. Like private.is_moderator(), but for admins only.
CREATE FUNCTION private.is_admin()
RETURNS BOOLEAN
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = ''
AS $$
  SELECT private.is_active_member()
  AND EXISTS (
    SELECT
    FROM public.profiles
    WHERE id = auth.uid() AND role = 'admin'
  );
$$;

REVOKE EXECUTE ON FUNCTION private.is_admin() FROM PUBLIC, anon;

-- As before (20261110130000_report_and_hide_updates.sql), with groups added. A new report also tells
-- every active moderator and admin, once (NOTIF-01's type, with the report's id as its dedupe key).
CREATE OR REPLACE FUNCTION public.report_content(
  target_type text,
  target_id uuid,
  reason text,
  note text DEFAULT NULL::text
)
RETURNS uuid
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
declare
  owner uuid;
  report_id uuid;
begin
  if not private.is_active_member() then
    raise exception 'NOT_ACTIVE' using errcode = '42501';
  end if;

  if report_content.target_type = 'activity' then
    select a.organizer_id into owner
    from public.activities as a
    where a.id = report_content.target_id and a.hidden_at is null;
  elsif report_content.target_type = 'profile' then
    select p.id into owner
    from public.profiles as p
    where p.id = report_content.target_id and p.status = 'active';
  elsif report_content.target_type = 'activity_update' then
    -- An update to an activity, or to a group (GRP-04), when neither it nor where it was posted is
    -- hidden.
    select u.author_id into owner
    from public.activity_updates as u
    left join public.activities as a on a.id = u.activity_id
    left join public.groups as g on g.id = u.group_id
    where
      u.id = report_content.target_id
      and u.hidden_at is null
      and a.hidden_at is null
      and g.hidden_at is null;
  elsif report_content.target_type = 'group' then
    -- A group that isn't hidden (MOD-08). Its owner can't report it.
    select g.owner_id into owner
    from public.groups as g
    where g.id = report_content.target_id and g.hidden_at is null;
  end if;

  if not found then
    raise exception 'REPORT_TARGET_NOT_FOUND' using errcode = 'P0002';
  end if;

  if owner = auth.uid() then
    raise exception 'REPORT_OWN' using errcode = '22023';
  end if;

  if exists (
    select
    from public.reports as r
    where
      r.reporter_id = auth.uid()
      and r.target_type = report_content.target_type
      and r.target_id = report_content.target_id
  ) then
    raise exception 'ALREADY_REPORTED' using errcode = '23505';
  end if;

  if (
    select count(*)
    from public.reports as r
    where r.reporter_id = auth.uid() and r.created_at > now() - interval '24 hours'
  ) >= 10 then
    raise exception 'REPORT_QUOTA_EXCEEDED' using errcode = 'P0001';
  end if;

  insert into public.reports (reporter_id, target_type, target_id, reason, note)
  values (
    auth.uid(),
    report_content.target_type,
    report_content.target_id,
    report_content.reason,
    nullif(trim(report_content.note), '')
  )
  returning id into report_id;

  perform private.notify(
    array(
      select p.id
      from public.profiles as p
      where p.role in ('moderator', 'admin') and p.status = 'active' and p.id <> auth.uid()
    ),
    'report_received',
    null,
    jsonb_build_object('kind', report_content.target_type, 'href', '/mod'),
    'report-received:' || report_id
  );

  return report_id;
end;
$$;

-- Moderators' notes on what's reported (MOD-08). Only moderators and admins read them, and writes go
-- through add_moderator_note().
CREATE TABLE public.moderator_notes (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  target_type text NOT NULL CHECK (
    target_type IN ('activity', 'profile', 'activity_update', 'group')
  ),
  target_id uuid NOT NULL,
  author_id uuid REFERENCES public.profiles (id)
    ON DELETE SET NULL,
  body text NOT NULL CHECK (char_length(trim(body)) BETWEEN 1 AND 500),
  created_at timestamptz NOT NULL DEFAULT now()
);

CREATE INDEX moderator_notes_target_idx
ON public.moderator_notes (target_type, target_id, created_at);

ALTER TABLE public.moderator_notes ENABLE ROW LEVEL SECURITY;

CREATE POLICY "Moderators read notes" ON public.moderator_notes
FOR SELECT
TO authenticated
USING (private.is_moderator());

-- Adds a note to what's reported. Returns its id.
CREATE FUNCTION public.add_moderator_note(target_type text, target_id uuid, body text)
RETURNS uuid
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
declare
  note_id uuid;
begin
  if not private.is_moderator() then
    raise exception 'NOT_MODERATOR' using errcode = '42501';
  end if;

  if not (
    (add_moderator_note.target_type = 'activity' and exists (select from public.activities as a where a.id = add_moderator_note.target_id))
    or (add_moderator_note.target_type = 'profile' and exists (select from public.profiles as p where p.id = add_moderator_note.target_id))
    or (add_moderator_note.target_type = 'activity_update' and exists (select from public.activity_updates as u where u.id = add_moderator_note.target_id))
    or (add_moderator_note.target_type = 'group' and exists (select from public.groups as g where g.id = add_moderator_note.target_id))
  ) then
    raise exception 'REPORT_TARGET_NOT_FOUND' using errcode = 'P0002';
  end if;

  insert into public.moderator_notes (target_type, target_id, author_id, body)
  values (add_moderator_note.target_type, add_moderator_note.target_id, auth.uid(), trim(add_moderator_note.body))
  returning id into note_id;

  return note_id;
end;
$$;

REVOKE EXECUTE ON FUNCTION public.add_moderator_note(text, uuid, text) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.add_moderator_note(text, uuid, text) TO authenticated;

-- The audit log, for admins, filtered by who did it and what it was about (MOD-08). Newest first.
CREATE FUNCTION public.admin_audit_log(
  actor uuid DEFAULT NULL,
  target uuid DEFAULT NULL,
  lim INTEGER DEFAULT 50
)
RETURNS TABLE (
  id BIGINT,
  created_at timestamptz,
  action text,
  target_type text,
  target_id uuid,
  reason text,
  actor_name text
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
begin
  if not private.is_admin() then
    raise exception 'NOT_ADMIN' using errcode = '42501';
  end if;

  return query
  select
    l.id,
    l.created_at,
    l.action,
    l.target_type,
    l.target_id,
    l.reason,
    p.display_name
  from private.audit_log as l
  left join public.profiles as p on p.id = l.actor_id
  where
    (admin_audit_log.actor is null or l.actor_id = admin_audit_log.actor)
    and (admin_audit_log.target is null or l.target_id = admin_audit_log.target)
  order by l.created_at desc, l.id desc
  limit least(greatest(admin_audit_log.lim, 1), 200);
end;
$$;

REVOKE EXECUTE ON FUNCTION public.admin_audit_log(uuid, uuid, INTEGER) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.admin_audit_log(uuid, uuid, INTEGER) TO authenticated;

-- Admins change a member's role, with a reason that goes to the audit log. private.set_member_role()
-- keeps the last admin in place.
CREATE FUNCTION public.admin_set_role(user_id uuid, role text, reason text)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
begin
  if not private.is_admin() then
    raise exception 'NOT_ADMIN' using errcode = '42501';
  end if;

  perform private.set_member_role(admin_set_role.user_id, admin_set_role.role, admin_set_role.reason);
end;
$$;

REVOKE EXECUTE ON FUNCTION public.admin_set_role(uuid, text, text) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.admin_set_role(uuid, text, text) TO authenticated;

-- Admins rename, switch on and off, and order categories and tags. A new tag is added with its id.
CREATE FUNCTION public.admin_save_category(id text, name text, is_active BOOLEAN)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
begin
  if not private.is_admin() then
    raise exception 'NOT_ADMIN' using errcode = '42501';
  end if;

  update public.categories as c
  set name = admin_save_category.name, is_active = admin_save_category.is_active, updated_at = now()
  where c.id = admin_save_category.id;

  if not found then
    raise exception 'CATEGORY_NOT_FOUND' using errcode = 'P0002';
  end if;
end;
$$;

REVOKE EXECUTE ON FUNCTION public.admin_save_category(text, text, BOOLEAN) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.admin_save_category(text, text, BOOLEAN) TO authenticated;

CREATE FUNCTION public.admin_save_tag(id text, name text, is_active BOOLEAN, sort_order INTEGER)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
begin
  if not private.is_admin() then
    raise exception 'NOT_ADMIN' using errcode = '42501';
  end if;

  insert into public.tags as t (id, name, is_active, sort_order)
  values (admin_save_tag.id, admin_save_tag.name, admin_save_tag.is_active, admin_save_tag.sort_order)
  on conflict on constraint tags_pkey do update
  set
    name = excluded.name,
    is_active = excluded.is_active,
    sort_order = excluded.sort_order,
    updated_at = now();
end;
$$;

REVOKE EXECUTE ON FUNCTION public.admin_save_tag(text, text, BOOLEAN, INTEGER) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.admin_save_tag(text, text, BOOLEAN, INTEGER) TO authenticated;
