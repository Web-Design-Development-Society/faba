// Notification preferences (NOTIF-10). The pgTAP tests cover what a type that's off does to a
// notification, and that cancellations always come.
import { expect, expectAccessible, test } from './fixtures';

test('a member turns a type off, and it stays off', async ({ page, signInAs }) => {
  await signInAs('member');
  await page.goto('/me/notifications');

  const alerts = page.getByRole('group', { name: 'Tell me about' });
  const newPeople = alerts.getByRole('checkbox', { name: /New people going/ });
  await expect(newPeople).toBeChecked();
  await expect(alerts.getByText('Cancelled: always on')).toBeVisible();
  await expectAccessible(page);

  await newPeople.uncheck();
  await page.getByRole('button', { name: 'Save', exact: true }).click();
  await expect(page.getByText('Saved.', { exact: true })).toBeVisible();
  await expect(alerts.getByRole('checkbox', { name: /New people going/ })).not.toBeChecked();

  await page.reload();
  await expect(alerts.getByRole('checkbox', { name: /New people going/ })).not.toBeChecked();
  await expectAccessible(page);

  // Turned back on.
  await alerts.getByRole('checkbox', { name: /New people going/ }).check();
  await page.getByRole('button', { name: 'Save', exact: true }).click();
  await expect(page.getByText('Saved.', { exact: true })).toBeVisible();
  await expect(alerts.getByRole('checkbox', { name: /New people going/ })).toBeChecked();
});
