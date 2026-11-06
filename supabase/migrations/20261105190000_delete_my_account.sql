-- Deleting my account (PROF-05). Design document sections 9.14, 10.1 and 10.5. A member deletes
-- their own account in two steps. This function cancels their upcoming activities, removes their
-- RSVPs and writes the audit row. Then the Worker deletes their auth user with the admin API, and
-- the foreign keys do the rest:
-- - their profile and private profile are deleted (ON DELETE CASCADE)
-- - activities keep no organizer, and show "Former member" (ON DELETE SET NULL), as do their
--   reports and the moderation records that name them
-- The audit log keeps their ID but no personal data (MOD-05).

-- Prepares the signed-in member's account for deletion. Running it again finds nothing more to
-- cancel or remove, so the Worker can retry when deleting the auth user fails. Any signed-in member
-- with a profile can, whatever their status.
CREATE FUNCTION public.delete_my_account()
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
declare
  cancelled integer;
  removed integer;
begin
  if not exists (select from public.profiles as p where p.id = auth.uid()) then
    raise exception 'ACCOUNT_NOT_FOUND' using errcode = 'P0002';
  end if;

  -- Activities they organize that haven't started. Their attendees still find them, cancelled.
  update public.activities as a
  set status = 'cancelled', cancel_reason = 'Its organizer left FABA.', cancelled_at = now()
  where a.organizer_id = auth.uid() and a.status = 'published' and a.starts_at > now();
  get diagnostics cancelled = row_count;

  -- Their RSVPs, with the going counts that rsvp() keeps (ADR-008).
  update public.activities as a
  set going_count = a.going_count - 1
  from public.rsvps as r
  where r.activity_id = a.id and r.user_id = auth.uid() and r.status = 'going';

  delete from public.rsvps as r
  where r.user_id = auth.uid();
  get diagnostics removed = row_count;

  perform private.audit(
    'delete_account',
    'profile',
    auth.uid(),
    NULL,
    jsonb_build_object('activities_cancelled', cancelled, 'rsvps_removed', removed)
  );
end;
$$;

GRANT EXECUTE ON FUNCTION public.delete_my_account() TO authenticated;
