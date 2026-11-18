// Date filters (SRCH-02), in the Date button's list (UI-09). Discover has other tests' activities
// too, so the first two tests search for a word only their own activities have, where the filters
// work the same. The unit tests in time.test.ts cover the ranges on each day of the week.
import type { Page } from '@playwright/test';
import { rexburgDate, whenRange } from '../../src/lib/time';
import { expect, expectAccessible, test } from './fixtures';

const HOUR = 60 * 60 * 1000;
const word = () => `w${crypto.randomUUID().slice(0, 8)}`;
const filters = (page: Page) => page.getByRole('navigation', { name: 'Filters' });
const button = (page: Page, name: 'Category' | 'Date') =>
  filters(page).locator('summary', { hasText: new RegExp(`^${name}`) });
/** Opens the Category or Date list and taps `choice`. */
async function choose(page: Page, list: 'Category' | 'Date', choice: string) {
  await button(page, list).click();
  await filters(page).getByRole('link', { name: choice, exact: true }).click();
}

test('This weekend combines with a category and search', async ({ page, signInAs, host }) => {
  await signInAs('member');
  const tag = word();
  // Sunday at 11 PM is this weekend, whatever day it is now.
  const sunday = whenRange('weekend', new Date()).before.getTime() - HOUR;
  const at = (time: number) => new Date(time).toISOString();
  await host.post({ title: `Hike ${tag}`, category_id: 'outdoors', starts_at: at(sunday) });
  await host.post({ title: `Board games ${tag}`, category_id: 'games', starts_at: at(sunday) });
  await host.post({ title: `Next hike ${tag}`, starts_at: at(sunday + 7 * 24 * HOUR) });

  await page.goto(`/search?q=${tag}`);
  await expect(button(page, 'Date')).toHaveText('Date');
  await button(page, 'Date').click();
  // Any time is chosen until something else is.
  await expect(filters(page).getByRole('link', { name: 'Any time' })).toHaveAttribute(
    'aria-current',
    'page'
  );
  await expectAccessible(page);
  await filters(page).getByRole('link', { name: 'This weekend' }).click();
  await expect(page).toHaveURL(`/search?q=${tag}&when=weekend`);
  await expect(button(page, 'Date')).toHaveText('Date: This weekend');
  await expect(page.getByText(`Hike ${tag}`, { exact: true })).toBeVisible();
  await expect(page.getByText(`Board games ${tag}`)).toBeVisible();
  await expect(page.getByText(`Next hike ${tag}`)).toHaveCount(0);

  await choose(page, 'Category', 'Outdoors');
  await expect(page).toHaveURL(`/search?q=${tag}&when=weekend&cat=outdoors`);
  await expect(page.getByText(`Hike ${tag}`, { exact: true })).toBeVisible();
  await expect(page.getByText(`Board games ${tag}`)).toHaveCount(0);

  // Any time takes the dates off and keeps the category.
  await choose(page, 'Date', 'Any time');
  await expect(page).toHaveURL(`/search?q=${tag}&cat=outdoors`);
  await expect(page.getByText(`Next hike ${tag}`)).toBeVisible();
});

test('Pick dates takes a custom range', async ({ page, signInAs, host }) => {
  await signInAs('member');
  const tag = word();
  const soon = Date.now() + 2 * 24 * HOUR;
  await host.post({ title: `Soon ${tag}`, starts_at: new Date(soon).toISOString() });
  await host.post({
    title: `Later ${tag}`,
    starts_at: new Date(soon + 3 * 24 * HOUR).toISOString(),
  });
  const day = rexburgDate(new Date(soon));

  await page.goto(`/search?q=${tag}`);
  await button(page, 'Date').click();
  await filters(page).getByLabel('From').fill(day);
  await filters(page).getByLabel('To').fill(day);
  await filters(page).getByRole('button', { name: 'Show activities' }).click();
  await expect(page).toHaveURL(`/search?q=${tag}&from=${day}&to=${day}`);
  await expect(page.getByText(`Soon ${tag}`)).toBeVisible();
  await expect(page.getByText(`Later ${tag}`)).toHaveCount(0);
  await expect(button(page, 'Date')).toHaveText(/^Date: /);
});

test('Discover says what nothing matches, and the filters can be combined', async ({
  page,
  signInAs,
}) => {
  await signInAs('member');
  // The sample data and the other tests have nothing in Other.
  await page.goto('/discover?cat=other&when=today');
  await expect(filters(page).locator('summary')).toHaveText(['Category: Other', 'Date: Today']);
  await expect(page.getByText('Nothing matches Other today.')).toBeVisible();
  // Beside the filters, and with the message.
  const clear = page.getByRole('link', { name: 'Clear filters' });
  await expect(clear).toHaveCount(2);
  for (const link of await clear.all()) await expect(link).toHaveAttribute('href', '/discover');
  await expectAccessible(page);
});

test('links from before UI-09 still work, without spots or tags', async ({ page, signInAs }) => {
  await signInAs('member');
  await page.goto('/discover?when=weekend&spots=1&tag=free');
  await expect(button(page, 'Date')).toHaveText('Date: This weekend');
  // Spots and tags are ignored, and choosing again leaves them out.
  await choose(page, 'Date', 'Today');
  await expect(page).toHaveURL('/discover?when=today');
});

test("Category's and Date's lists have the same room around their choices", async ({
  page,
  signInAs,
}) => {
  await signInAs('member');
  await page.goto('/discover');
  for (const list of ['Category', 'Date'] as const) {
    await button(page, list).click();
    const panel = filters(page).locator('details[open] .panel');
    await expect(panel).toBeVisible();
    await expect(panel).toHaveCSS('padding', '12px');
    await button(page, list).click();
  }
});
