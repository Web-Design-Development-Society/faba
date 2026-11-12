// Playoff brackets (LEAG-09). The pgTAP tests cover seeding, the round order and the champion.
// Written while E2E is paused; not yet run.
import { expect, expectAccessible, test } from './fixtures';

test('an organizer starts a playoff bracket from the standings', async ({ page, poster }) => {
  // The poster fixture signs in a fresh account, with its own group quota.
  void poster;
  await page.goto('/leagues/new');
  await page.getByLabel('League name').fill(`Bracket ${crypto.randomUUID().slice(0, 6)}`);
  await page.getByLabel('Category').selectOption('sports');
  await page.getByRole('button', { name: 'Start league' }).click();
  await expect(page).toHaveURL(/\/groups\/.+\/seasons$/);

  await page.getByLabel('Season name').fill('Fall 2030');
  await page.getByLabel('First day').fill('2030-09-01');
  await page.getByLabel('Last day').fill('2030-11-30');
  await page.getByRole('button', { name: 'Start season' }).click();
  await expect(page.getByRole('status')).toHaveText('Season started.');

  for (const name of ['Reds', 'Blues', 'Greens', 'Golds']) {
    await page.getByLabel('Team name').last().fill(name);
    await page.getByRole('button', { name: 'Add team' }).click();
    await expect(page.getByRole('status')).toHaveText('Team added.');
  }

  await page.getByLabel('First playoff day').fill('2030-10-05');
  await page.getByLabel('Playoff venue').fill('Gym');
  await page.getByRole('button', { name: 'Make the round robin' }).click();
  await expect(page.getByRole('status')).toHaveText('Schedule made.');
  await expectAccessible(page);
});
