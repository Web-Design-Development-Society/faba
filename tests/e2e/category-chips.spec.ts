// Discover's category chips (ACT-06).
import type { Page } from '@playwright/test';
import { expect, expectAccessible, test } from './fixtures';

const HOUR = 60 * 60 * 1000;

// Other tests post at the same time, so each activity has a title of its own.
const named = (title: string) => `${title} ${crypto.randomUUID().slice(0, 8)}`;
const chip = (page: Page, name: string) =>
  page.getByRole('navigation', { name: 'Filters' }).getByRole('link', { name, exact: true });

/** Whether every card in the feed is in `category`. */
async function expectOnly(page: Page, category: string) {
  const cards = page.locator('[data-feed] li');
  await expect(cards).not.toHaveCount(0);
  await expect(cards.getByRole('img', { name: category, exact: true })).toHaveCount(
    await cards.count()
  );
}

test('a chip shows only its category, and says it is chosen', async ({ page, signInAs, host }) => {
  await signInAs('member');
  const game = named('Board game night');
  const hike = named('Sunrise hike');
  // Soon, so they're on the first page.
  const soon = new Date(Date.now() + HOUR).toISOString();
  await host.post({ title: game, category_id: 'games', starts_at: soon });
  await host.post({ title: hike, starts_at: soon });

  await page.goto('/discover');
  const chips = page.getByRole('navigation', { name: 'Filters' });
  await expect(chips.getByRole('link').first()).toHaveText('All');
  await expect(chip(page, 'All')).toHaveAttribute('aria-current', 'page');
  // The row scrolls sideways, and the page doesn't.
  expect(await chips.getByRole('list').evaluate((row) => row.scrollWidth > row.clientWidth)).toBe(
    true
  );
  expect(
    await page.evaluate(
      () => document.documentElement.scrollWidth - document.documentElement.clientWidth
    )
  ).toBe(0);

  await chip(page, 'Games').click();
  await expect(page).toHaveURL('/discover?cat=games');
  await expect(page).toHaveTitle('Games · Discover · FABA');
  await expect(chip(page, 'Games')).toHaveAttribute('aria-current', 'page');
  await expect(chips.locator('[aria-current]')).toHaveCount(1);
  await expect(page.getByRole('link', { name: game })).toBeVisible();
  await expect(page.getByText(hike)).toHaveCount(0);
  await expectOnly(page, 'Games');
  // Posting from here starts in Games.
  await expect(page.getByRole('link', { name: 'Post', exact: true })).toHaveAttribute(
    'href',
    '/activities/new?cat=games'
  );
  await expectAccessible(page);

  await chip(page, 'All').click();
  await expect(page).toHaveURL('/discover');
  await expect(page.getByRole('link', { name: hike })).toBeVisible();
});

test('a category with nothing coming up invites the member to post one', async ({
  page,
  signInAs,
}) => {
  await signInAs('member');
  // The sample data and the other tests have nothing in Other, the last chip.
  await page.goto('/discover?cat=other');
  await expect(chip(page, 'Other')).toBeInViewport({ ratio: 1 });
  await expect(page.getByText('Nothing matches Other.')).toBeVisible();
  await expect(page.getByRole('link', { name: 'Clear filters' })).toHaveAttribute(
    'href',
    '/discover'
  );
  await expectAccessible(page);

  await page.getByRole('link', { name: 'Post one' }).click();
  await expect(page).toHaveURL('/activities/new?cat=other');
  await expect(page.getByRole('radio', { name: 'Other' })).toBeChecked();
});

test('Show more stays in the category', async ({ page, signInAs, host }) => {
  await signInAs('member');
  // More than a page of Family, a month from now.
  const { error } = await host.admin.from('activities').insert(
    Array.from({ length: 21 }, (_, n) => ({
      organizer_id: host.id,
      category_id: 'family',
      title: named('Family picnic'),
      starts_at: new Date(Date.now() + (30 * 24 + n) * HOUR).toISOString(),
      location_name: 'Porter Park',
    }))
  );
  if (error) throw new Error(`Posting failed: ${error.message}`);

  await page.goto('/discover?cat=family');
  const more = page.getByRole('link', { name: 'Show more' });
  await expect(more).toHaveAttribute('href', /^\/discover\?after=.+&id=.+&cat=family$/);
  await more.click();
  await expect(page.locator('[data-feed] li').nth(20)).toBeVisible();
  await expectOnly(page, 'Family');
});

test('a category that is not offered shows them all', async ({ page, signInAs }) => {
  await signInAs('member');
  // Online is turned off for now (ADR-017).
  await page.goto('/discover?cat=online');
  await expect(page).toHaveURL('/discover');
  await expect(chip(page, 'All')).toHaveAttribute('aria-current', 'page');
});

test.describe('without JavaScript', () => {
  test.use({ javaScriptEnabled: false });

  test('a chip is a link that filters the feed', async ({ page, signInAs }) => {
    await signInAs('member');
    await page.goto('/discover');
    await chip(page, 'Outdoors').click();
    await expect(page).toHaveURL('/discover?cat=outdoors');
    await expect(chip(page, 'Outdoors')).toHaveAttribute('aria-current', 'page');
    await expectOnly(page, 'Outdoors');
  });
});
