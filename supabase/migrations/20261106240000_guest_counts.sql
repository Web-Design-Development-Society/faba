-- Keeping guest_total right (RSVP-06) when RSVPs go without rsvp(): deleting an account
-- (PROF-05) and moving one to a new account (OPS-01). Both as before
-- (20261106210000_maybe_counts.sql), taking the guests of a going RSVP they drop off the activity's
-- guest total. An RSVP that moves keeps its guests.

CREATE OR REPLACE FUNCTION public.delete_my_account()
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

  -- Their RSVPs, with the going and maybe counts and the guests that rsvp() keeps (ADR-008).
  update public.activities as a
  set
    going_count = a.going_count - (r.status = 'going')::integer,
    maybe_count = a.maybe_count - (r.status = 'maybe')::integer,
    guest_total = a.guest_total - r.guest_count
  from public.rsvps as r
  where r.activity_id = a.id and r.user_id = auth.uid() and r.status in ('going', 'maybe');

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

CREATE OR REPLACE FUNCTION private.transfer_account(from_user uuid, to_user uuid, reason text)
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

  -- RSVPs to an activity the new account has also answered go, with the going or maybe count and
  -- the guests they held.
  update public.activities as a
  set
    going_count = a.going_count - (r.status = 'going')::integer,
    maybe_count = a.maybe_count - (r.status = 'maybe')::integer,
    guest_total = a.guest_total - r.guest_count
  from public.rsvps as r
  where
    r.activity_id = a.id
    and r.user_id = from_user
    and r.status in ('going', 'maybe')
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
