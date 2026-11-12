-- Comments on activities (ACT-12). A flat list of plain-text questions and answers under an
-- activity, so a member doesn't have to email the organizer. Members read the comments on the
-- activities they can see, unless they're hidden. Members post and delete their own through
-- functions (ADR-004), and comments are reportable like updates. Moderators hide them with a reason,
-- which the author sees, and the reports on them are dealt with too.

CREATE TABLE public.activity_comments (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  activity_id uuid NOT NULL REFERENCES public.activities (id)
    ON DELETE CASCADE,
  -- Null after the author deletes their account (PROF-05).
  author_id uuid REFERENCES public.profiles (id)
    ON DELETE SET NULL,
  body text NOT NULL CHECK (char_length(trim(body)) BETWEEN 1 AND 500),
  created_at timestamptz NOT NULL DEFAULT now(),
  hidden_at timestamptz,
  hidden_reason text CHECK (char_length(hidden_reason) <= 500),
  hidden_by uuid REFERENCES public.profiles (id)
    ON DELETE SET NULL
);

CREATE INDEX activity_comments_activity_idx ON public.activity_comments (activity_id, created_at);

ALTER TABLE public.activity_comments ENABLE ROW LEVEL SECURITY;

-- The same as updates: active members read the comments on activities they can see, unless the
-- comment is hidden. Moderators read hidden ones too, to review them.
CREATE POLICY "Active members read comments on activities they can see" ON public.activity_comments
FOR SELECT
TO authenticated
USING (
  (SELECT private.is_active_member())
  AND (activity_comments.hidden_at IS NULL OR (SELECT private.is_moderator()))
  AND EXISTS (SELECT FROM public.activities AS a WHERE a.id = activity_comments.activity_id)
);

-- Posts `body` as a comment on an activity that isn't hidden. Returns the comment's id. A member
-- can post up to 20 comments an hour, so a spammer is slowed down, and a moderator can still act.
CREATE FUNCTION public.post_comment(activity_id uuid, body text)
RETURNS uuid
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
declare
  clean_body text := trim(post_comment.body);
  comment_id uuid;
begin
  if not private.is_active_member() then
    raise exception 'NOT_ACTIVE' using errcode = '42501';
  end if;

  if clean_body is null or char_length(clean_body) not between 1 and 500 then
    raise exception 'INVALID_COMMENT' using errcode = '22023';
  end if;

  -- Nobody sees a hidden activity, so nobody can comment on one.
  if not exists (
    select from public.activities as a
    where a.id = post_comment.activity_id and a.hidden_at is null
  ) then
    raise exception 'ACTIVITY_NOT_FOUND' using errcode = 'P0002';
  end if;

  if (
    select count(*)
    from public.activity_comments as c
    where c.author_id = auth.uid() and c.created_at > now() - interval '1 hour'
  ) >= 20 then
    raise exception 'COMMENT_QUOTA_EXCEEDED' using errcode = 'P0001';
  end if;

  insert into public.activity_comments (activity_id, author_id, body)
  values (post_comment.activity_id, auth.uid(), clean_body)
  returning id into comment_id;

  return comment_id;
end;
$$;

REVOKE EXECUTE ON FUNCTION public.post_comment(uuid, text) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.post_comment(uuid, text) TO authenticated;

-- Deletes the signed-in member's own comment. Moderators hide comments instead, so the reason
-- stays on record.
CREATE FUNCTION public.delete_comment(comment_id uuid)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
declare
  posted public.activity_comments;
begin
  select * into posted
  from public.activity_comments as c
  where c.id = delete_comment.comment_id;

  if not found then
    raise exception 'COMMENT_NOT_FOUND' using errcode = 'P0002';
  end if;

  if posted.author_id is distinct from auth.uid() then
    raise exception 'NOT_COMMENT_AUTHOR' using errcode = '42501';
  end if;

  delete from public.activity_comments as c
  where c.id = posted.id;
end;
$$;

REVOKE EXECUTE ON FUNCTION public.delete_comment(uuid) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.delete_comment(uuid) TO authenticated;

-- Hiding and unhiding a comment (ACT-12), with a reason that the author sees and that goes to the
-- audit log. Hiding deals with the comment's open reports, as it does for updates.
CREATE FUNCTION public.moderate_hide_comment(comment_id uuid, reason text)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
declare
  posted public.activity_comments;
  why text := nullif(trim(moderate_hide_comment.reason), '');
  actioned integer;
begin
  if not private.is_moderator() then
    raise exception 'NOT_MODERATOR' using errcode = '42501';
  end if;

  if why is null then
    raise exception 'REASON_REQUIRED' using errcode = '22023';
  end if;

  select * into posted
  from public.activity_comments as c
  where c.id = moderate_hide_comment.comment_id
  for update;

  if not found then
    raise exception 'COMMENT_NOT_FOUND' using errcode = 'P0002';
  end if;

  if posted.hidden_at is not null then
    raise exception 'COMMENT_ALREADY_HIDDEN' using errcode = '22023';
  end if;

  update public.activity_comments as c
  set hidden_at = now(), hidden_reason = why, hidden_by = auth.uid()
  where c.id = posted.id;

  update public.reports as r
  set status = 'actioned', resolved_by = auth.uid(), resolved_at = now(), resolution_note = why
  where r.target_type = 'comment' and r.target_id = posted.id and r.status = 'open';
  get diagnostics actioned = row_count;

  perform private.audit(
    'hide',
    'comment',
    posted.id,
    why,
    jsonb_build_object('activity_id', posted.activity_id, 'reports_actioned', actioned)
  );
end;
$$;

REVOKE EXECUTE ON FUNCTION public.moderate_hide_comment(uuid, text) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.moderate_hide_comment(uuid, text) TO authenticated;

CREATE FUNCTION public.moderate_unhide_comment(comment_id uuid, reason text)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
declare
  posted public.activity_comments;
  why text := nullif(trim(moderate_unhide_comment.reason), '');
begin
  if not private.is_moderator() then
    raise exception 'NOT_MODERATOR' using errcode = '42501';
  end if;

  if why is null then
    raise exception 'REASON_REQUIRED' using errcode = '22023';
  end if;

  select * into posted
  from public.activity_comments as c
  where c.id = moderate_unhide_comment.comment_id
  for update;

  if not found then
    raise exception 'COMMENT_NOT_FOUND' using errcode = 'P0002';
  end if;

  if posted.hidden_at is null then
    raise exception 'COMMENT_NOT_HIDDEN' using errcode = '22023';
  end if;

  update public.activity_comments as c
  set hidden_at = null, hidden_reason = null, hidden_by = null
  where c.id = posted.id;

  perform private.audit(
    'unhide',
    'comment',
    posted.id,
    why,
    jsonb_build_object('activity_id', posted.activity_id)
  );
end;
$$;

REVOKE EXECUTE ON FUNCTION public.moderate_unhide_comment(uuid, text) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.moderate_unhide_comment(uuid, text) TO authenticated;

-- Comments can be reported, like updates (ACT-12).
ALTER TABLE public.reports DROP CONSTRAINT reports_target_type_check;
ALTER TABLE public.reports
ADD CONSTRAINT reports_target_type_check
  CHECK (target_type IN ('activity', 'profile', 'activity_update', 'group', 'comment'));

-- The audit log names comments as targets.
ALTER TABLE private.audit_log DROP CONSTRAINT audit_log_target_type_check;
ALTER TABLE private.audit_log
ADD CONSTRAINT audit_log_target_type_check
  CHECK (target_type IN ('activity', 'profile', 'report', 'activity_update', 'group', 'comment'));

-- As in 20261114120000_moderation_tools.sql, with comments added. A comment's author can't report it,
-- and a hidden comment or one on a hidden activity can't be reported.
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
  elsif report_content.target_type = 'comment' then
    -- A comment that isn't hidden, on an activity that isn't (ACT-12).
    select c.author_id into owner
    from public.activity_comments as c
    join public.activities as a on a.id = c.activity_id
    where
      c.id = report_content.target_id
      and c.hidden_at is null
      and a.hidden_at is null;
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
