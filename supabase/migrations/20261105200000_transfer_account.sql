-- Moving a member's activities and RSVPs to their new account (OPS-01). Design document section
-- 9.7: a brand-new Google account for the same person is a new FABA account, and "an admin can
-- transfer organized activities with an audited runbook". A merge feature isn't planned. An admin
-- runs it in the Supabase dashboard with docs/runbooks/transfer-account.md.

-- Moves what `from_user` organizes, and their RSVPs, to `to_user`, with a reason for the audit
-- log. Where both accounts answered the same activity, the new account's answer stays. It changes
-- neither profile, and doesn't delete the old account. Like set_member_role(), only the database
-- owner can call it.
CREATE FUNCTION private.transfer_account(from_user uuid, to_user uuid, reason text)
RETURNS void
LANGUAGE plpgsql
SET search_path = ''
AS $$
declare
  why text := nullif(trim(transfer_account.reason), '');
  organized integer;
  moved integer;
  dropped integer;
begin
  if why is null then
    raise exception 'REASON_REQUIRED' using errcode = '22023';
  end if;

  if from_user = to_user then
    raise exception 'SAME_ACCOUNT' using errcode = '22023';
  end if;

  if (select count(*) from public.profiles as p where p.id in (from_user, to_user)) < 2 then
    raise exception 'MEMBER_NOT_FOUND' using errcode = 'P0002';
  end if;

  update public.activities as a
  set organizer_id = to_user
  where a.organizer_id = from_user;
  get diagnostics organized = row_count;

  -- RSVPs to an activity the new account has also answered go, with the going count they held.
  update public.activities as a
  set going_count = a.going_count - 1
  from public.rsvps as r
  where
    r.activity_id = a.id
    and r.user_id = from_user
    and r.status = 'going'
    and exists (
      select from public.rsvps as mine where mine.activity_id = a.id and mine.user_id = to_user
    );

  delete from public.rsvps as r
  where
    r.user_id = from_user
    and exists (
      select from public.rsvps as mine
      where mine.activity_id = r.activity_id and mine.user_id = to_user
    );
  get diagnostics dropped = row_count;

  update public.rsvps as r
  set user_id = to_user
  where r.user_id = from_user;
  get diagnostics moved = row_count;

  perform private.audit(
    'data_fix',
    'profile',
    from_user,
    why,
    jsonb_build_object(
      'transferred_to', to_user,
      'activities', organized,
      'rsvps_moved', moved,
      'rsvps_dropped', dropped
    )
  );
end;
$$;

REVOKE EXECUTE
ON FUNCTION private.transfer_account(uuid, uuid, text)
FROM PUBLIC, anon, authenticated, service_role;
