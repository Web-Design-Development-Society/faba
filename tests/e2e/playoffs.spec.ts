// Playoff brackets (LEAG-09). The pgTAP tests cover seeding, the round order and the champion. This
// checks the page: the round robin comes first, and the bracket waits for it.
import { expect, expectAccessible, test } from './fixtures';

test('the playoff bracket waits until the regular season is scored', async ({ page, poster }) => {
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

  // The bracket starts only once every regular game has a score, so this checks the round robin
  // comes first. Scoring every game is covered by the pgTAP tests.
  await page.getByLabel('First game day').fill('2030-09-07');
  await page.getByLabel('Place').fill('Gym');
  await page.getByRole('button', { name: 'Make the round robin' }).click();
  await expect(page.getByRole('status')).toHaveText('Schedule made.');
  await expect(page.getByRole('button', { name: 'Start the bracket' })).toHaveCount(0);
  await expectAccessible(page);
});
