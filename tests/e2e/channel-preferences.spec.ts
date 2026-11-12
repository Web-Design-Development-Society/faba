// Email preferences: which types reach a member by email, quiet hours and the reminder lead time
// (NOTIF-13). The pgTAP tests cover the rules; this checks the settings page saves and comes back.
// Email delivery isn't built yet, so the page says so. Written while E2E is paused; not yet run.
import { expect, expectAccessible, test } from './fixtures';

test('a member turns off email for a type, sets quiet hours, and picks a reminder time', async ({
  page,
  signInAs,
}) => {
  await signInAs('member');
  await page.goto('/me/notifications');
  await expect(page.getByText('Email delivery is coming soon.')).toBeVisible();

  const byEmail = page.getByRole('group', { name: 'Email me about' });
  const newPeople = byEmail.getByRole('checkbox', { name: /New people going/ });
  // Earlier runs may have left it off, so start from on.
  if (!(await newPeople.isChecked())) await newPeople.check();
  await newPeople.uncheck();

  await page.getByLabel('Quiet hours from').fill('22:00');
  await page.getByLabel('to', { exact: true }).fill('06:30');
  await page.getByLabel('Reminders').selectOption('6');
  await page.getByRole('button', { name: 'Save email settings' }).click();
  await expect(page.getByText('Saved.', { exact: true })).toBeVisible();
  await expectAccessible(page);

  await page.reload();
  await expect(byEmail.getByRole('checkbox', { name: /New people going/ })).not.toBeChecked();
  await expect(page.getByLabel('Quiet hours from')).toHaveValue('22:00');
  await expect(page.getByLabel('to', { exact: true })).toHaveValue('06:30');
  await expect(page.getByLabel('Reminders')).toHaveValue('6');
});
