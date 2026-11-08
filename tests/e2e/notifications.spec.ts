// The notification center (NOTIF-01). The pgTAP tests cover marking notifications read.
import { expect, expectAccessible, test } from './fixtures';

const minutesAgo = (minutes: number) => new Date(Date.now() - minutes * 60 * 1000).toISOString();

test('the center has new and earlier alerts, and opening one marks it read', async ({
  page,
  poster,
  host,
}) => {
  const id = await host.post();
  await poster.admin.from('notifications').insert([
    {
      recipient_id: poster.id,
      type: 'activity_changed',
      activity_id: id,
      created_at: minutesAgo(5),
    },
    { recipient_id: poster.id, type: 'reminder', activity_id: id, created_at: minutesAgo(1) },
    // Its activity is gone.
    {
      recipient_id: poster.id,
      type: 'activity_cancelled',
      created_at: minutesAgo(60),
      read_at: minutesAgo(30),
    },
  ]);

  await page.goto('/notifications');
  const fresh = page.getByRole('region', { name: 'New' });
  const earlier = page.getByRole('region', { name: 'Earlier' });
  await expect(fresh.getByRole('button')).toHaveText([
    /Unread: Reminder\s*Sunrise hike up the R/,
    /Unread: Time or place changed\s*Sunrise hike up the R/,
  ]);
  await expect(earlier.getByRole('button')).toHaveText([/Cancelled\s*No longer available/]);
  await expectAccessible(page);

  await fresh.getByRole('button', { name: /Time or place changed/ }).click();
  await expect(page).toHaveURL(`/activities/${id}`);
  await page.goto('/notifications');
  await expect(fresh.getByRole('button')).toHaveCount(1);

  await page.getByRole('button', { name: 'Mark all read' }).click();
  await expect(page.getByRole('status')).toHaveText('All caught up.');
  await expect(fresh).toHaveCount(0);
  await expect(earlier.getByRole('button')).toHaveCount(3);
});

test('with no alerts, the center says so', async ({ page, poster }) => {
  expect(poster.id).toBeTruthy();
  await page.goto('/notifications');
  await expect(
    page.getByText("You're all caught up. We'll let you know when plans change.")
  ).toBeVisible();
  await expect(page.getByRole('button', { name: 'Mark all read' })).toHaveCount(0);
});
