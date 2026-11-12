-- Web Push (NOTIF-20). Design document sections 6.9 and 9.12, and ADR-007. A member turns push on
-- for a phone or computer under Me → Notifications, and that device's subscription is stored here.
-- A push is a delivery of an in-app notification, never a notification of its own: when
-- private.notify() writes a row, or brings one back (a repeat with the same dedupe key), a trigger
-- queues one delivery for each of the recipient's devices. The Worker's Cron Trigger claims the
-- queue every minute, sends each push, and reports back (src/lib/server/push/send.ts).
--
-- Push is opt-in twice: turning it on for a device, then by type. The urgent types are on by
-- default, and the rest are off until the member turns them on. Cancellations always push, as they
-- always come in the app. A type that's off in the app makes no notification, so it never pushes.

-- The types a member can choose for push, and the in-app sub_needed type that was missing here
-- (LEAG-06 added it to notifications, but not to the preferences, so turning it off failed).
ALTER TABLE public.notification_preferences
DROP CONSTRAINT notification_preferences_type_check;

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
      'sub_needed',
      'report_received'
    )
  );

ALTER TABLE public.notification_preferences
DROP CONSTRAINT notification_preferences_channel_check;

ALTER TABLE public.notification_preferences
ADD CONSTRAINT notification_preferences_channel_check CHECK (channel IN ('in_app', 'push'));

-- Whether `type` pushes before a member chooses: the urgent changes to plans they're in. It matches
-- PUSH_DEFAULT_TYPES in src/lib/notifications.ts.
CREATE FUNCTION private.push_on_by_default(type text)
RETURNS BOOLEAN
LANGUAGE sql
IMMUTABLE
SET search_path = ''
AS $$
  SELECT push_on_by_default.type IN (
    'activity_changed',
    'activity_cancelled',
    'activity_restored',
    'reminder',
    'rsvp_promoted',
    'rsvp_removed',
    'sub_needed'
  );
$$;

-- Whether a notification of `type` pushes to `user_id`'s devices: always for a cancellation, or as
-- they chose, or by default.
CREATE FUNCTION private.push_enabled(user_id uuid, type text)
RETURNS BOOLEAN
LANGUAGE sql
STABLE
SET search_path = ''
AS $$
  SELECT push_enabled.type = 'activity_cancelled'
  OR coalesce(
    (
      SELECT p.enabled
      FROM public.notification_preferences AS p
      WHERE p.user_id = push_enabled.user_id AND p.type = push_enabled.type AND p.channel = 'push'
    ),
    private.push_on_by_default(push_enabled.type)
  );
$$;

-- One row for each device a member turned push on for. The endpoint is the push service's address
-- for that device, and p256dh and auth are the keys that encrypt what's sent to it (RFC 8291).
CREATE TABLE public.push_subscriptions (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id uuid NOT NULL REFERENCES public.profiles (id)
    ON DELETE CASCADE,
  endpoint text NOT NULL UNIQUE CHECK (endpoint ~ '^https?://' AND length(endpoint) <= 1000),
  -- A P-256 public key (65 bytes) and a 16-byte secret, base64url without padding.
  p256dh text NOT NULL CHECK (p256dh ~ '^[A-Za-z0-9_-]{87}$'),
  auth text NOT NULL CHECK (auth ~ '^[A-Za-z0-9_-]{22}$'),
  created_at timestamptz NOT NULL DEFAULT now(),
  last_sent_at timestamptz
);

CREATE INDEX push_subscriptions_user_idx ON public.push_subscriptions (user_id);

ALTER TABLE public.push_subscriptions ENABLE ROW LEVEL SECURITY;

-- Members see their own devices, so the page knows push is on somewhere. Writes go through the
-- functions below.
CREATE POLICY "Members read their own push devices" ON public.push_subscriptions
FOR SELECT
TO authenticated
USING (user_id = (SELECT auth.uid()));

-- One row for each push to send: a notification, to one device. A repeat of the notification sends
-- it again. Only the sender reads these, with the secret key, so there are no policies.
CREATE TABLE public.notification_deliveries (
  id BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  notification_id uuid NOT NULL REFERENCES public.notifications (id)
    ON DELETE CASCADE,
  subscription_id uuid NOT NULL REFERENCES public.push_subscriptions (id)
    ON DELETE CASCADE,
  channel text NOT NULL DEFAULT 'push' CHECK (channel = 'push'),
  status text NOT NULL DEFAULT 'pending' CHECK (status IN ('pending', 'sent', 'skipped', 'failed')),
  attempts INTEGER NOT NULL DEFAULT 0,
  next_attempt_at timestamptz NOT NULL DEFAULT now(),
  sent_at timestamptz,
  last_error text,
  created_at timestamptz NOT NULL DEFAULT now(),
  UNIQUE (notification_id, subscription_id)
);

CREATE INDEX notification_deliveries_due_idx ON public.notification_deliveries (next_attempt_at)
WHERE status = 'pending';

CREATE INDEX notification_deliveries_subscription_idx
ON public.notification_deliveries (subscription_id);

ALTER TABLE public.notification_deliveries ENABLE ROW LEVEL SECURITY;

-- Queues a push of the new or returning notification to each of its recipient's devices, if they
-- push its type. A repeat while one is still queued just queues it once.
CREATE FUNCTION private.queue_push()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
begin
  insert into public.notification_deliveries (notification_id, subscription_id)
  select new.id, s.id
  from public.push_subscriptions as s
  where s.user_id = new.recipient_id and private.push_enabled(new.recipient_id, new.type)
  on conflict (notification_id, subscription_id) do update
  set status = 'pending', attempts = 0, next_attempt_at = now(), sent_at = null, last_error = null;
  return null;
end;
$$;

CREATE TRIGGER notifications_queue_push
AFTER INSERT ON public.notifications
FOR EACH ROW
EXECUTE FUNCTION private.queue_push();

-- private.notify() brings a notification back by setting created_at again.
CREATE TRIGGER notifications_queue_push_again
AFTER UPDATE OF created_at ON public.notifications
FOR EACH ROW
WHEN (new.created_at IS DISTINCT FROM old.created_at)
EXECUTE FUNCTION private.queue_push();

-- Turns push on for the signed-in member's device. A device belongs to whoever turned it on last,
-- so on a shared computer the one before stops getting pushes, and whatever was still queued for
-- them goes too. A member keeps at most 10 devices: the oldest go.
CREATE FUNCTION public.save_push_subscription(endpoint text, p256dh text, auth_secret text)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
begin
  if not private.is_active_member() then
    raise exception 'NOT_ACTIVE' using errcode = '42501';
  end if;

  delete from public.push_subscriptions as s where s.endpoint = save_push_subscription.endpoint;

  -- The clock, not the transaction's start, so devices saved together still have an order.
  insert into public.push_subscriptions (user_id, endpoint, p256dh, auth, created_at)
  values (
    (select auth.uid()),
    save_push_subscription.endpoint,
    save_push_subscription.p256dh,
    save_push_subscription.auth_secret,
    clock_timestamp()
  );

  delete from public.push_subscriptions as s
  where s.id in (
    select o.id
    from public.push_subscriptions as o
    where o.user_id = (select auth.uid())
    order by o.created_at desc, o.id
    offset 10
  );
end;
$$;

REVOKE EXECUTE ON FUNCTION public.save_push_subscription(text, text, text) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.save_push_subscription(text, text, text) TO authenticated;

-- Turns push off for one of the signed-in member's devices.
CREATE FUNCTION public.remove_push_subscription(endpoint text)
RETURNS void
LANGUAGE sql
SECURITY DEFINER
SET search_path = ''
AS $$
  DELETE FROM public.push_subscriptions AS s
  WHERE s.endpoint = remove_push_subscription.endpoint AND s.user_id = (SELECT auth.uid());
$$;

REVOKE EXECUTE ON FUNCTION public.remove_push_subscription(text) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.remove_push_subscription(text) TO authenticated;

-- Saves which types push to the signed-in member's devices. Only what differs from the default is
-- stored, so a type turned on that's on by default has no row. Cancellations always push.
CREATE FUNCTION public.set_push_preferences(turned_on text[], turned_off text[])
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
begin
  if not private.is_active_member() then
    raise exception 'NOT_ACTIVE' using errcode = '42501';
  end if;

  delete from public.notification_preferences as p
  where p.user_id = (select auth.uid()) and p.channel = 'push';

  insert into public.notification_preferences (user_id, type, channel, enabled)
  select (select auth.uid()), t.type, 'push', TRUE
  from unnest(set_push_preferences.turned_on) as t (type)
  where t.type <> 'activity_cancelled' and not private.push_on_by_default(t.type)
  union
  select (select auth.uid()), t.type, 'push', FALSE
  from unnest(set_push_preferences.turned_off) as t (type)
  where t.type <> 'activity_cancelled' and private.push_on_by_default(t.type);
end;
$$;

REVOKE EXECUTE ON FUNCTION public.set_push_preferences(text[], text[]) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.set_push_preferences(text[], text[]) TO authenticated;

-- For the sender only: claims up to `max_count` pushes that are due, with what each needs to be
-- encrypted and worded. A notification already read in the app, or more than a day old, isn't
-- pushed. Each claim pushes its next try 5 minutes out, so a push the sender never reports on
-- comes round again.
CREATE FUNCTION public.claim_push_deliveries(max_count INTEGER DEFAULT 50)
RETURNS TABLE (
  delivery_id BIGINT,
  attempts INTEGER,
  endpoint text,
  p256dh text,
  auth text,
  notification_id uuid,
  type text,
  payload jsonb,
  activity_id uuid,
  group_slug text
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
#variable_conflict use_column
begin
  update public.notification_deliveries as d
  set status = 'skipped'
  from public.notifications as n
  where
    d.notification_id = n.id
    and d.status = 'pending'
    and (n.read_at is not null or n.created_at < now() - interval '1 day');

  return query
  with
    due as (
      select d.id
      from public.notification_deliveries as d
      where d.status = 'pending' and d.next_attempt_at <= now()
      order by d.next_attempt_at, d.id
      limit claim_push_deliveries.max_count
      for update skip locked
    ),
    claimed as (
      update public.notification_deliveries as d
      set attempts = d.attempts + 1, next_attempt_at = now() + interval '5 minutes'
      from due
      where d.id = due.id
      returning d.id, d.attempts, d.notification_id, d.subscription_id
    )
  select
    c.id,
    c.attempts,
    s.endpoint,
    s.p256dh,
    s.auth,
    n.id,
    n.type,
    n.payload,
    n.activity_id,
    g.slug::text
  from claimed as c
  join public.push_subscriptions as s on s.id = c.subscription_id
  join public.notifications as n on n.id = c.notification_id
  left join public.groups as g on g.id = n.group_id
  order by c.id;
end;
$$;

REVOKE EXECUTE ON FUNCTION public.claim_push_deliveries(INTEGER) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.claim_push_deliveries(INTEGER) TO service_role;

-- For the sender only: how a push went. `sent`, or `gone` when the push service says the device
-- has unsubscribed, which forgets the device. `retry` tries again after 2, 4, 8 and 16 minutes,
-- and gives up after the fifth try. `failed` gives up now.
CREATE FUNCTION public.finish_push_delivery(
  delivery_id BIGINT,
  outcome text,
  error text DEFAULT NULL
)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
declare
  device uuid;
begin
  select d.subscription_id into device
  from public.notification_deliveries as d
  where d.id = finish_push_delivery.delivery_id;

  if not found then
    return;
  end if;

  case finish_push_delivery.outcome
    when 'sent' then
      update public.notification_deliveries as d
      set status = 'sent', sent_at = now(), last_error = null
      where d.id = finish_push_delivery.delivery_id;

      update public.push_subscriptions as s set last_sent_at = now() where s.id = device;
    when 'gone' then
      delete from public.push_subscriptions as s where s.id = device;
    when 'retry' then
      update public.notification_deliveries as d
      set
        status = case when d.attempts >= 5 then 'failed' else 'pending' end,
        next_attempt_at = now() + make_interval(mins => power(2, d.attempts)::INTEGER),
        last_error = left(finish_push_delivery.error, 500)
      where d.id = finish_push_delivery.delivery_id;
    when 'failed' then
      update public.notification_deliveries as d
      set status = 'failed', last_error = left(finish_push_delivery.error, 500)
      where d.id = finish_push_delivery.delivery_id;
    else
      raise exception 'UNKNOWN_OUTCOME' using errcode = '22023';
  end case;
end;
$$;

REVOKE EXECUTE
ON FUNCTION public.finish_push_delivery(BIGINT, text, text)
FROM PUBLIC, anon, authenticated;

GRANT EXECUTE ON FUNCTION public.finish_push_delivery(BIGINT, text, text) TO service_role;
