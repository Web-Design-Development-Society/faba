// FABA's look (UI-02): selected things are FABA blue, never black, and the bottom bar keeps its five
// items, each with a line icon over its label.
import { expect, expectAccessible, test } from './fixtures';

const BLUE = 'rgb(11, 91, 211)';

test('selected things are FABA blue, and the bar keeps its five items', async ({
  page,
  signInAs,
}) => {
  await signInAs('member');
  await page.goto('/discover');

  const bar = page.getByRole('navigation', { name: 'Main' });
  await expect(bar.getByRole('link')).toHaveText(['Discover', 'Plans', 'Post', /^Alerts/, 'Me']);
  await expect(bar.locator('svg')).toHaveCount(5);
  const here = bar.getByRole('link', { name: 'Discover' });
  await expect(here).toHaveAttribute('aria-current', 'page');
  await expect(here).toHaveCSS('color', BLUE);
  await expect(bar.locator('.post .circle')).toHaveCSS('background-color', BLUE);

  const activities = page
    .getByRole('navigation', { name: 'Discover' })
    .getByRole('link', { name: 'Activities' });
  await expect(activities).toHaveCSS('background-color', BLUE);
  // Any time, the date chosen until another is, is FABA blue in the Date list.
  const filters = page.getByRole('navigation', { name: 'Filters' });
  await filters.locator('summary', { hasText: /^Date/ }).click();
  await expect(filters.getByRole('link', { name: 'Any time' })).toHaveCSS('background-color', BLUE);
  await page.keyboard.press('Escape');

  // The mark and the wordmark go to Discover, and Search is an icon button with its name.
  await expect(page.getByRole('link', { name: 'FABA' })).toHaveAttribute('href', '/discover');
  await expect(page.getByRole('link', { name: 'Search' })).toBeVisible();
  await expectAccessible(page);
});
