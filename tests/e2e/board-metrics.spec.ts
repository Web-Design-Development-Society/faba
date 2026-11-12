// The board's metrics page (ANLY-01). The pgTAP tests cover the figures and the 10-person rule. Written
// while E2E is paused; not yet run.
import { expect, expectAccessible, test } from './fixtures';

test('a moderator sees the board metrics, and a member is turned away', async ({
  page,
  signInAs,
}) => {
  await signInAs('moderator');
  await page.goto('/admin/board');
  await expect(page.getByRole('heading', { level: 1, name: 'Board metrics' })).toBeVisible();
  await expectAccessible(page);

  await signInAs('member');
  const response = await page.goto('/admin/board');
  expect(response?.status()).toBe(403);
  await expect(page.getByText('Only moderators and admins can see these figures.')).toBeVisible();
});
