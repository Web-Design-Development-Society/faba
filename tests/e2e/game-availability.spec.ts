// Game availability (LEAG-07). The pgTAP tests cover who can answer for a game, and that the answer
// is the RSVP. Written while E2E is paused; not yet run.
import { expect, expectAccessible, test } from './fixtures';

test('a player on a team says they can play a game, and it is in Plans', async ({
  page,
  poster,
}) => {
  // The poster fixture signs in a fresh account, with its own group quota.
  void poster;
  await page.goto('/leagues/new');
  await page.getByLabel('League name').fill(`Bowling ${crypto.randomUUID().slice(0, 6)}`);
  await page.getByLabel('Category').selectOption('games');
  await page.getByRole('button', { name: 'Start league' }).click();
  await expect(page).toHaveURL(/\/groups\/.+\/seasons$/);

  await page.getByLabel('Season name').fill('Winter 2030');
  await page.getByLabel('First day').fill('2030-01-05');
  await page.getByLabel('Last day').fill('2030-03-31');
  await page.getByRole('button', { name: 'Start season' }).click();
  await page.getByRole('button', { name: 'Join season' }).click();

  for (const name of ['Reds', 'Blues']) {
    await page.getByLabel('Team name').last().fill(name);
    await page.getByRole('button', { name: 'Add team' }).click();
    await expect(page.getByRole('status')).toHaveText('Team added.');
  }
  await page.getByLabel('Team for').first().selectOption({ label: 'Reds' });
  await page.getByRole('button', { name: 'Move' }).first().click();

  await page.getByLabel('First game day').fill('2030-01-08');
  await page.getByLabel('Place').fill('Lanes 4');
  await page.getByRole('button', { name: 'Make the round robin' }).click();

  await page.getByRole('button', { name: 'Can play' }).first().click();
  await expect(page.getByRole('status')).toHaveText('Saved. Your answer is in your Plans.');
  await expectAccessible(page);
});
