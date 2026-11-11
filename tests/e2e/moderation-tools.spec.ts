// Moderation and admin tools (MOD-08). The pgTAP tests cover who can do what in the database, and
// that each report reaches the moderators.
import { expect, expectAccessible, test } from './fixtures';

test('an admin sees categories, tags and the audit log', async ({ page, signInAs }) => {
  await signInAs('admin');
  await page.goto('/admin');
  await expect(page.getByRole('heading', { level: 1, name: 'Admin' })).toBeVisible();
  await expect(page.getByRole('heading', { name: 'Categories' })).toBeVisible();
  await expect(page.getByRole('heading', { name: 'Tags' })).toBeVisible();
  await expectAccessible(page);

  await page.goto('/admin/audit');
  await expect(page.getByRole('heading', { level: 1, name: 'Audit log' })).toBeVisible();
  await expect(page.getByLabel('Who did it')).toBeVisible();
  await expectAccessible(page);
});

test('a member can not open the admin pages', async ({ page, signInAs }) => {
  await signInAs('member');
  const response = await page.goto('/admin');
  expect(response?.status()).toBe(403);
  await expect(page.getByText('Only admins can open this.')).toBeVisible();

  const audit = await page.goto('/admin/audit');
  expect(audit?.status()).toBe(403);
  await expect(page.getByText('Only admins can read the audit log.')).toBeVisible();
});
