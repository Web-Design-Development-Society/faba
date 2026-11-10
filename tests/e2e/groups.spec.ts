// Interest groups (GRP-01). The pgTAP tests cover the limits, addresses and who reads what.
import { expect, expectAccessible, test } from './fixtures';

test('a member starts a group from Discover and lands on it as its owner', async ({
  page,
  poster,
}) => {
  expect(poster.id).toBeTruthy();
  const name = `Trail Runners ${crypto.randomUUID().slice(0, 6)}`;
  await page.goto('/discover');
  await page
    .getByRole('navigation', { name: 'Discover' })
    .getByRole('link', { name: 'Groups' })
    .click();
  await expect(page).toHaveURL('/groups');
  await page.getByRole('link', { name: 'Start a group' }).first().click();
  await expect(page).toHaveURL('/groups/new');
  await expectAccessible(page);

  await page.getByLabel('Name').fill(name);
  await page.getByRole('radio', { name: 'Outdoors' }).check();
  await page.getByLabel("What it's about (optional)").fill('Easy miles on Saturdays.');
  await page.getByRole('radio', { name: 'People you approve' }).check();
  await page.getByRole('button', { name: 'Start group' }).click();

  await expect(page).toHaveURL(/\/groups\/trail-runners-[a-z0-9-]+$/);
  await expect(page.getByRole('status')).toHaveText('Group started!');
  await expect(page.getByRole('heading', { level: 1, name })).toBeVisible();
  await expect(page.getByText('You started this group')).toBeVisible();
  await expect(page.getByText('Ask to join')).toBeVisible();
  await expectAccessible(page);

  await page.getByRole('link', { name: 'Back to Groups' }).click();
  await expect(page.getByRole('link', { name })).toBeVisible();
});

test('an unknown group is not available', async ({ page, poster }) => {
  expect(poster.id).toBeTruthy();
  const response = await page.goto('/groups/no-such-group');
  expect(response?.status()).toBe(404);
  await expect(page.getByRole('heading', { name: 'Not available' })).toBeVisible();
});
