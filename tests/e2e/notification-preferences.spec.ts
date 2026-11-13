// Notification preferences (NOTIF-10). The pgTAP tests cover what a type that's off does to a
// notification, and that cancellations always come.
import { expect, expectAccessible, test } from './fixtures';

// A new member of its own, since the other sizes run this at the same time and would change the
// shared member's choices under it.
test('a member turns a type off, and it stays off', async ({ page, poster }) => {
  // From Me.
  await page.goto('/me');
  await page.getByRole('link', { name: 'Notifications', exact: true }).click();
  await expect(page).toHaveURL('/me/notifications');

  const alerts = page.getByRole('group', { name: 'Tell me about' });
  const newPeople = alerts.getByRole('checkbox', { name: /New people going/ });
  await expect(newPeople).toBeChecked();
  await expect(alerts.getByText('Cancelled: always on')).toBeVisible();
  await expectAccessible(page);

  await newPeople.uncheck();
  await page.getByRole('button', { name: 'Save', exact: true }).click();
  await expect(page.getByText('Saved.', { exact: true })).toBeVisible();
  await expect(alerts.getByRole('checkbox', { name: /New people going/ })).not.toBeChecked();

  const { data: saved } = await poster.admin
    .from('notification_preferences')
    .select('type, channel, enabled')
    .eq('user_id', poster.id);
  expect(saved).toEqual([{ type: 'new_attendees', channel: 'in_app', enabled: false }]);

  await page.reload();
  await expect(alerts.getByRole('checkbox', { name: /New people going/ })).not.toBeChecked();
  await expectAccessible(page);

  // Turned back on.
  await alerts.getByRole('checkbox', { name: /New people going/ }).check();
  await page.getByRole('button', { name: 'Save', exact: true }).click();
  await expect(page.getByText('Saved.', { exact: true })).toBeVisible();
  await expect(alerts.getByRole('checkbox', { name: /New people going/ })).toBeChecked();
});
