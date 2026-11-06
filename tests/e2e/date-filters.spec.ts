// Date filters (SRCH-02). Discover has other tests' activities too, so the first test searches for
// a word only its own activities have, where the chips work the same. The unit tests in
// time.test.ts cover the ranges on each day of the week.
import { whenRange } from '../../src/lib/time';
import { expect, expectAccessible, test } from './fixtures';

const HOUR = 60 * 60 * 1000;
const word = () => `w${crypto.randomUUID().slice(0, 8)}`;

test('the weekend chip combines with a category and search', async ({ page, signInAs, host }) => {
  await signInAs('member');
  const tag = word();
  // Sunday at 11 PM is this weekend, whatever day it is now.
  const sunday = whenRange('weekend', new Date()).before.getTime() - HOUR;
  const at = (time: number) => new Date(time).toISOString();
  await host.post({ title: `Hike ${tag}`, category_id: 'outdoors', starts_at: at(sunday) });
  await host.post({ title: `Board games ${tag}`, category_id: 'games', starts_at: at(sunday) });
  await host.post({ title: `Next hike ${tag}`, starts_at: at(sunday + 7 * 24 * HOUR) });

  await page.goto(`/search?q=${tag}`);
  const chips = page.getByRole('navigation', { name: 'Filters' });
  const chip = (name: string) => chips.getByRole('link', { name, exact: true });
  await chip('This weekend').click();
  await expect(page).toHaveURL(`/search?q=${tag}&when=weekend`);
  await expect(chip('This weekend')).toHaveAttribute('aria-current', 'page');
  await expect(page.getByText(`Hike ${tag}`, { exact: true })).toBeVisible();
  await expect(page.getByText(`Board games ${tag}`)).toBeVisible();
  await expect(page.getByText(`Next hike ${tag}`)).toHaveCount(0);

  await chip('Outdoors').click();
  await expect(page).toHaveURL(`/search?q=${tag}&when=weekend&cat=outdoors`);
  await expect(page.getByText(`Hike ${tag}`, { exact: true })).toBeVisible();
  await expect(page.getByText(`Board games ${tag}`)).toHaveCount(0);
  await expectAccessible(page);

  // Tapping a chosen chip takes it off.
  await chip('This weekend').click();
  await expect(page).toHaveURL(`/search?q=${tag}&cat=outdoors`);
  await expect(page.getByText(`Next hike ${tag}`)).toBeVisible();
});

test('Discover says what nothing matches, and chips can be combined', async ({
  page,
  signInAs,
}) => {
  await signInAs('member');
  // The sample data and the other tests have nothing in Other.
  await page.goto('/discover?cat=other&when=today');
  const chips = page.getByRole('navigation', { name: 'Filters' });
  await expect(chips.locator('[aria-current]')).toHaveText(['Today', 'Other']);
  await expect(page.getByText('Nothing matches Other today.')).toBeVisible();
  await expect(page.getByRole('link', { name: 'Clear filters' })).toHaveAttribute(
    'href',
    '/discover'
  );
  await expectAccessible(page);
});
