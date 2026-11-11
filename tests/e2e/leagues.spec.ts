// Leagues and seasons (LEAG-01). The pgTAP tests cover who can start a season, one active season
// at a time, and ladders being one person.
import { expect, expectAccessible, test } from './fixtures';

test('a member starts a league, and starts its first season', async ({ page, poster }) => {
  // The poster fixture signs in a fresh account, with its own group quota.
  void poster;
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
  await expect(page.getByRole('heading', { name: 'Summer 2026', exact: true })).toBeVisible();
  await expectAccessible(page);
});

test('a member signs up for a season, and withdraws', async ({ page, poster }) => {
  // The poster fixture signs in a fresh account, with its own group quota.
  void poster;
  await page.goto('/leagues/new');
  await page.getByLabel('League name').fill(`Chess Club ${crypto.randomUUID().slice(0, 6)}`);
  await page.getByLabel('Category').selectOption('games');
  await page.getByRole('button', { name: 'Start league' }).click();
  await expect(page).toHaveURL(/\/groups\/.+\/seasons$/);

  await page.getByLabel('Season name').fill('Winter 2026');
  await page.getByLabel('First day').fill('2026-12-01');
  await page.getByLabel('Last day').fill('2027-02-28');
  await page.getByRole('button', { name: 'Start season' }).click();
  await expect(page.getByRole('status')).toHaveText('Season started.');

  await page.getByLabel('A free agent').check();
  await page.getByLabel('Note, optional').fill('Free on weeknights');
  await expectAccessible(page);
  await page.getByRole('button', { name: 'Join season' }).click();
  await expect(page.getByRole('status')).toHaveText("You're signed up for this season.");
  await expect(page.getByText("You're signed up as a free agent.")).toBeVisible();

  await page.getByRole('button', { name: 'Withdraw' }).click();
  await expect(page.getByRole('status')).toHaveText("You've withdrawn from this season.");
  await expect(page.getByRole('button', { name: 'Join season' })).toBeVisible();
});

test('an organizer makes a team and moves a player onto it', async ({ page, poster }) => {
  // The poster fixture signs in a fresh account, with its own group quota.
  void poster;
  await page.goto('/leagues/new');
  await page.getByLabel('League name').fill(`Trivia Night ${crypto.randomUUID().slice(0, 6)}`);
  await page.getByLabel('Category').selectOption('games');
  await page.getByRole('button', { name: 'Start league' }).click();
  await expect(page).toHaveURL(/\/groups\/.+\/seasons$/);

  await page.getByLabel('Season name').fill('Spring 2027');
  await page.getByLabel('First day').fill('2027-03-01');
  await page.getByLabel('Last day').fill('2027-05-31');
  await page.getByRole('button', { name: 'Start season' }).click();
  await expect(page.getByRole('status')).toHaveText('Season started.');

  await page.getByRole('button', { name: 'Join season' }).click();
  await expect(page.getByRole('status')).toHaveText("You're signed up for this season.");

  await page.getByLabel('Team name').fill('Reds');
  await page.getByRole('button', { name: 'Add team' }).click();
  await expect(page.getByRole('status')).toHaveText('Team added.');
  await expect(page.getByRole('heading', { name: 'Reds' })).toBeVisible();

  await page.getByLabel('Team for').first().selectOption({ label: 'Reds' });
  await page.getByRole('button', { name: 'Move' }).first().click();
  await expect(page.getByRole('status')).toHaveText('Player moved.');
  await expectAccessible(page);
});
