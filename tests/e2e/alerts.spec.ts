// The Alerts badge (NOTIF-01). The pgTAP tests cover the unread count.
import { expect, test } from './fixtures';

test('Alerts shows the unread count, stops at 9+, and refreshes every minute', async ({
  page,
  poster,
}) => {
  const notify = (count: number) =>
    poster.admin.from('notifications').insert(
      Array.from({ length: count }, () => ({
        recipient_id: poster.id,
        type: 'reminder',
        payload: { title: 'Board game night' },
      }))
    );
  await page.clock.install();
  await notify(3);

  await page.goto('/discover');
  const alerts = page
    .getByRole('navigation', { name: 'Main' })
    .getByRole('link', { name: /^Alerts/ });
  await expect(alerts).toHaveAccessibleName('Alerts, 3 unread');
  await expect(alerts.locator('[data-badge]')).toHaveText('3');

  await notify(8);
  await page.clock.fastForward(60 * 1000);
  await expect(alerts).toHaveAccessibleName('Alerts, 11 unread');
  await expect(alerts.locator('[data-badge]')).toHaveText('9+');
});
