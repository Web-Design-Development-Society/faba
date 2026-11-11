// Leagues and seasons (LEAG-01). The pgTAP tests cover who can start a season, one active season
// at a time, and ladders being one person.
import { expect, expectAccessible, test } from './fixtures';

test('a member starts a league, and starts its first season', async ({ page, signInAs }) => {
  await signInAs('member');
  await page.goto('/leagues/new');
  const name = `Pickle Ladder ${crypto.randomUUID().slice(0, 6)}`;
  await page.getByLabel('League name').fill(name);
  await page.getByLabel('Category').selectOption('sports');
  await expectAccessible(page);
  await page.getByRole('button', { name: 'Start league' }).click();

  await expect(page).toHaveURL(/\/groups\/.+\/seasons$/);
  await expect(page.getByRole('heading', { level: 1, name: `${name}: seasons` })).toBeVisible();
  await expect(page.getByText('No season is running right now.')).toBeVisible();

  await page.getByLabel('Season name').fill('Summer 2026');
  await page.getByLabel('First day').fill('2026-06-01');
  await page.getByLabel('Last day').fill('2026-08-31');
  await page.getByRole('button', { name: 'Start season' }).click();
  await expect(page.getByRole('status')).toHaveText('Season started.');
  await expect(page.getByRole('heading', { name: 'Summer 2026' })).toBeVisible();
  await expectAccessible(page);
});
