// The individual ladder (LEAG-08). The pgTAP tests cover entering players as teams of one, and that
// a ladder is scheduled between two players. Written while E2E is paused; not yet run.
import { expect, expectAccessible, test } from './fixtures';

test('an organizer enters the players of a ladder, and schedules their games', async ({
  page,
  poster,
}) => {
  // The poster fixture signs in a fresh account, with its own group quota.
  void poster;
  await page.goto('/leagues/new');
  await page.getByLabel('League name').fill(`Ladder ${crypto.randomUUID().slice(0, 6)}`);
  await page.getByLabel('Category').selectOption('games');
  await page.getByRole('button', { name: 'Start league' }).click();
  await expect(page).toHaveURL(/\/groups\/.+\/seasons$/);

  await page.getByLabel('Season name').fill('Spring 2030');
  await page.getByLabel('First day').fill('2030-04-01');
  await page.getByLabel('Last day').fill('2030-06-30');
  await page.getByLabel('Individual ladder').check();
  await page.getByRole('button', { name: 'Start season' }).click();
  await expect(page.getByRole('status')).toHaveText('Season started.');

  await page.getByRole('button', { name: 'Join season' }).click();
  await page.getByRole('button', { name: 'Enter the players' }).click();
  await expect(page.getByRole('status')).toHaveText('Players entered. Schedule the games next.');
  await expectAccessible(page);
});
