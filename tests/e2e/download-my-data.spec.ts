// Downloading my data (PRIV-01). The pgTAP tests cover the member's own data and the limit of three
// a day. Written while E2E is paused; not yet run.
import { expect, test } from './fixtures';

test('a member downloads a file of their own data', async ({ page, poster }) => {
  // The poster fixture signs in a fresh account, with its own export limit.
  void poster;
  await page.goto('/me');
  const download = page.waitForEvent('download');
  await page.getByRole('link', { name: 'Download my data' }).click();
  const file = await download;
  expect(file.suggestedFilename()).toBe('faba-my-data.json');
});
