// Notification preferences (NOTIF-10). The pgTAP tests cover what a type that's off does to a
// notification, and that cancellations always come.
import { expect, expectAccessible, test } from './fixtures';

test('a member turns a type off, and it stays off', async ({ page, signInAs }) => {
  await signInAs('member');
  await page.goto('/me/notifications');

  const newPeople = page.getByRole('checkbox', { name: /New people going/ });
  await expect(newPeople).toBeChecked();
  await expect(page.getByText('Cancelled: always on')).toBeVisible();
  await expectAccessible(page);

  await newPeople.uncheck();
  await page.getByRole('button', { name: 'Save' }).click();
  await expect(page.getByRole('status')).toHaveText('Saved.');
  await expect(page.getByRole('checkbox', { name: /New people going/ })).not.toBeChecked();

  await page.reload();
  await expect(page.getByRole('checkbox', { name: /New people going/ })).not.toBeChecked();
  await expectAccessible(page);

  // Turned back on.
  await page.getByRole('checkbox', { name: /New people going/ }).check();
  await page.getByRole('button', { name: 'Save' }).click();
  await expect(page.getByRole('status')).toHaveText('Saved.');
  await expect(page.getByRole('checkbox', { name: /New people going/ })).toBeChecked();
});
