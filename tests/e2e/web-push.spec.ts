// Web Push (NOTIF-20). A member turns push on under Me → Notifications, and an urgent change to an
// activity they're going to reaches their device, encrypted, the next time the Cron Trigger runs.
// The device is made up: the page's push subscription is replaced with one whose endpoint is a
// stand-in push service on localhost, which decrypts what the Worker sends (tests/e2e/push-service).
import { expect, test } from './fixtures';
import { decrypt, makeDevice, startPushService } from './push-service';

// Replacing the browser's push subscription needs Chromium's PushManager. WebKit's isn't there
// outside an installed web app.
test.skip(({ browserName }) => browserName !== 'chromium', 'Needs Chromium’s PushManager');

/** Runs the Worker's Cron Trigger once, as Cloudflare does every minute. */
async function runCron(baseURL: string) {
  const response = await fetch(`${baseURL}/cdn-cgi/handler/scheduled`);
  expect(response.ok).toBe(true);
}

test('a member turns push on, and an urgent change reaches their device', async ({
  page,
  baseURL,
  poster,
  crowd,
}) => {
  const service = await startPushService();
  try {
    const device = await makeDevice(`${service.url}/push/${crypto.randomUUID()}`);
    // The member allows notifications, and the browser's subscription is the made-up device's,
    // kept across reloads like a real one. Headless Chromium always says notifications are denied,
    // so the permission is made up too.
    await page.addInitScript(({ endpoint, p256dh, auth }) => {
      Object.defineProperty(Notification, 'permission', { get: () => 'granted' });
      Notification.requestPermission = async () => 'granted';
      const key = (text: string) =>
        Uint8Array.from(atob(text.replace(/-/g, '+').replace(/_/g, '/')), (c) => c.charCodeAt(0))
          .buffer;
      const made = {
        endpoint,
        expirationTime: null,
        options: { userVisibleOnly: true, applicationServerKey: null },
        getKey: (name: string) => key(name === 'p256dh' ? p256dh : auth),
        toJSON: () => ({ endpoint, expirationTime: null, keys: { p256dh, auth } }),
        unsubscribe: async () => {
          sessionStorage.removeItem('test-push');
          return true;
        },
      };
      PushManager.prototype.subscribe = async () => {
        sessionStorage.setItem('test-push', 'on');
        return made as unknown as PushSubscription;
      };
      PushManager.prototype.getSubscription = async () =>
        sessionStorage.getItem('test-push') ? (made as unknown as PushSubscription) : null;
    }, device);

    // Turning it on shows which types push. The urgent ones are on.
    await page.goto('/me/notifications');
    await page.getByRole('button', { name: 'Turn on for this device' }).click();
    await expect(page.getByText('Push is on for this device.')).toBeVisible();
    const pushes = page.getByRole('group', { name: 'Push to my devices' });
    await expect(pushes.getByRole('checkbox', { name: 'Time or place changed' })).toBeChecked();
    await expect(pushes.getByRole('checkbox', { name: 'New people going' })).not.toBeChecked();

    // They're going to a game night, and its organizer moves it.
    const [organizer] = await crowd(1);
    const title = `Game night ${crypto.randomUUID().slice(0, 8)}`;
    const { data: activityId, error } = await organizer.rpc('create_activity', {
      title,
      category_id: 'games',
      starts_at: new Date(Date.now() + 24 * 60 * 60 * 1000).toISOString(),
      location_name: 'Library',
    });
    expect(error).toBeNull();
    await poster.admin
      .from('rsvps')
      .insert({ activity_id: activityId, user_id: poster.id, status: 'going' });
    const { data: activity } = await poster.admin
      .from('activities')
      .select('version')
      .eq('id', activityId!)
      .single();
    const moved = await organizer.rpc('update_activity', {
      activity_id: activityId!,
      expected_version: activity!.version,
      patch: { location_name: 'Hart courts' },
    });
    expect(moved.error).toBeNull();

    await runCron(baseURL!);
    await expect.poll(() => service.received.length).toBe(1);
    const [push] = service.received;
    expect(push.headers['content-encoding']).toBe('aes128gcm');
    expect(push.headers.urgency).toBe('high');
    expect(push.headers.authorization).toMatch(/^vapid t=[\w-]+\.[\w-]+\.[\w-]+, k=[\w-]{87}$/);
    const message = JSON.parse(new TextDecoder().decode(await decrypt(push.body, device)));
    expect(message).toEqual({
      id: expect.any(String),
      title,
      body: 'Now at Hart courts (was Library)',
      url: `/notifications/${message.id}`,
    });

    // It's sent once.
    await runCron(baseURL!);
    expect(service.received).toHaveLength(1);

    // Tapping it opens the activity, and it's read in Alerts.
    await page.goto(message.url);
    await expect(page).toHaveURL(`/activities/${activityId}`);
    const { data: alert } = await poster.admin
      .from('notifications')
      .select('read_at')
      .eq('id', message.id)
      .single();
    expect(alert!.read_at).not.toBeNull();

    // Turning it off forgets the device.
    await page.goto('/me/notifications');
    await page.getByRole('button', { name: 'Turn off for this device' }).click();
    await expect(page.getByRole('button', { name: 'Turn on for this device' })).toBeVisible();
    await expect(page.getByRole('group', { name: 'Push to my devices' })).toHaveCount(0);
    const { count } = await poster.admin
      .from('push_subscriptions')
      .select('id', { count: 'exact', head: true })
      .eq('endpoint', device.endpoint);
    expect(count).toBe(0);
  } finally {
    await service.close();
  }
});

test('a member chooses which types push', async ({ page, poster }) => {
  // A device that already has push on. Nothing is sent to it here.
  await poster.admin.from('push_subscriptions').insert({
    user_id: poster.id,
    endpoint: `http://127.0.0.1:9/push/${crypto.randomUUID()}`,
    p256dh: `B${'A'.repeat(86)}`,
    auth: 'A'.repeat(22),
  });

  await page.goto('/me/notifications');
  const pushes = page.getByRole('group', { name: 'Push to my devices' });
  await pushes.getByRole('checkbox', { name: 'New people going' }).check();
  await pushes.getByRole('checkbox', { name: 'Reminder' }).uncheck();
  await page.getByRole('button', { name: 'Save push settings' }).click();
  await expect(page.getByRole('status').filter({ hasText: 'Saved.' })).toBeVisible();

  await expect(pushes.getByRole('checkbox', { name: 'New people going' })).toBeChecked();
  await expect(pushes.getByRole('checkbox', { name: 'Reminder' })).not.toBeChecked();
  // The in-app switches are untouched.
  await expect(
    page.getByRole('group', { name: 'Tell me about' }).getByRole('checkbox', { name: 'Reminder' })
  ).toBeChecked();
});
