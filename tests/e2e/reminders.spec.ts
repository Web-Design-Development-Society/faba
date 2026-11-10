// In-app reminders (NOTIF-07). The job runs in the database, so the pgTAP tests cover who's reminded
// and when. This checks the line in Alerts.
import { formatClock } from '../../src/lib/time';
import { expect, test } from './fixtures';

test('Alerts shows a reminder with the time and place', async ({ page, poster, host }) => {
  // An hour away, which is still today unless the test runs just before midnight.
  const startsAt = new Date(Date.now() + 60 * 60 * 1000);
  const id = await host.post({ starts_at: startsAt.toISOString(), location_name: 'Hart courts' });
  await poster.admin.from('notifications').insert({
    recipient_id: poster.id,
    type: 'reminder',
    activity_id: id,
    payload: {
      title: 'Sunrise hike up the R',
      starts_at: startsAt.toISOString(),
      location_name: 'Hart courts',
    },
  });

  await page.goto('/notifications');
  await expect(page.getByRole('region', { name: 'New' }).getByRole('button')).toHaveText([
    new RegExp(
      `Unread: Reminder: (today at ${formatClock(startsAt)}|.+), Hart courts\\s*Sunrise hike up the R`
    ),
  ]);
});
