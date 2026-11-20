// Discover's filters, tucked away behind Filters until the member wants them or a filter is on
// (UI-36). Search keeps them shown, and without JavaScript they're always shown. With a filter on,
// Clear filters and Follow are on a line of their own under Category and Date (UI-35, NOTIF-09).
import type { Page } from '@playwright/test';
import { expect, expectAccessible, test } from './fixtures';

const filters = (page: Page) => page.getByRole('navigation', { name: 'Filters' });
const toggle = (page: Page) => filters(page).getByRole('button', { name: 'Filters' });
const category = (page: Page) => filters(page).locator('summary', { hasText: /^Category/ });

test('Discover hides its filters until Filters shows them', async ({ page, signInAs }) => {
  await signInAs('member');
  await page.goto('/discover');

  // Hidden at first, with Filters at the right, level with the first day's heading. It's quiet
  // words in the display face, at least 44 px tall.
  await expect(toggle(page)).toHaveAttribute('aria-expanded', 'false');
  await expect(category(page)).toBeHidden();
  const [button, day] = [
    (await toggle(page).boundingBox())!,
    (await page.locator('[data-feed] h3').first().boundingBox())!,
  ];
  expect(Math.abs(button.y + button.height / 2 - (day.y + day.height / 2))).toBeLessThan(3);
  expect(Math.abs(button.x + button.width - (day.x + day.width))).toBeLessThan(1);
  expect(button.height).toBeGreaterThanOrEqual(44);
  await expect(toggle(page)).toHaveCSS('font-family', /^Anton/);
  await expect(toggle(page)).toHaveCSS('text-transform', 'uppercase');
  await expect(toggle(page)).toHaveCSS('background-color', 'rgba(0, 0, 0, 0)');
  // The first card is the page's full width, below it.
  const card = (await page.locator('[data-feed] li').first().boundingBox())!;
  expect(card.y).toBeGreaterThanOrEqual(button.y + button.height);
  expect(card.width).toBeCloseTo(day.width, 0);
  await expectAccessible(page);

  // Tapping it shows the row, with Filters at its right, level with Category.
  await toggle(page).click();
  await expect(toggle(page)).toHaveAttribute('aria-expanded', 'true');
  await expect(category(page)).toBeVisible();
  const [shown, first] = [
    (await toggle(page).boundingBox())!,
    (await category(page).boundingBox())!,
  ];
  expect(Math.abs(shown.y - first.y)).toBeLessThan(1);
  expect(shown.x).toBeGreaterThan(first.x + first.width);
  await expectAccessible(page);

  // Hiding it closes an open panel, and tapping it again hides the row.
  await category(page).click();
  const games = filters(page).getByRole('link', { name: 'Games', exact: true });
  await expect(games).toBeVisible();
  await toggle(page).click();
  await expect(toggle(page)).toHaveAttribute('aria-expanded', 'false');
  await expect(category(page)).toBeHidden();
  await toggle(page).click();
  await expect(category(page)).toBeVisible();
  await expect(games).toBeHidden();
});

test('Discover shows its filters when one is on', async ({ page, signInAs }) => {
  await signInAs('member');
  await page.goto('/discover?cat=outdoors');
  await expect(toggle(page)).toHaveAttribute('aria-expanded', 'true');
  await expect(category(page)).toHaveText('Category: Outdoors');
  await expect(category(page)).toBeVisible();
  const clear = filters(page).getByRole('link', { name: 'Clear filters' });
  const follow = filters(page).getByRole('button', { name: /^Follow/ });
  await expect(clear).toBeVisible();
  // Category and Date with Filters at the right, then Clear filters and Follow side by side.
  const [first, filtersBox, clearBox, followBox] = await Promise.all(
    [category(page), toggle(page), clear, follow].map(async (l) => (await l.boundingBox())!)
  );
  expect(Math.abs(filtersBox.y - first.y)).toBeLessThan(1);
  expect(clearBox.y).toBeGreaterThan(first.y + first.height);
  expect(Math.abs(followBox.y - clearBox.y)).toBeLessThan(1);
  expect(followBox.x).toBeGreaterThan(clearBox.x + clearBox.width);
  await expectAccessible(page);

  // And when the dates in the link don't work, to say so.
  await page.goto('/discover?from=2030-01-10&to=2030-01-01');
  await expect(toggle(page)).toHaveAttribute('aria-expanded', 'true');
  await expect(page.getByRole('alert')).toHaveText(/^Those dates don't work together\./);
  await expect(category(page)).toBeVisible();
});

test('Search keeps its filters shown', async ({ page, signInAs }) => {
  await signInAs('member');
  await page.goto('/search?q=hike');
  await expect(category(page)).toBeVisible();
  await expect(toggle(page)).toHaveCount(0);
});

test.describe('without JavaScript', () => {
  test.use({ javaScriptEnabled: false });

  test('Discover shows its filters, with no Filters button', async ({ page, signInAs }) => {
    await signInAs('member');
    await page.goto('/discover');
    await expect(category(page)).toBeVisible();
    await expect(toggle(page)).toHaveCount(0);
  });
});
