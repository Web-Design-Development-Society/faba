// FABA's look (UI-02, UI-14): the bottom bar keeps its five items, each with a line icon in a tile
// over its label, and the current tab and chosen date are FABA blue. The cut-paper look puts
// headings in Anton, in capitals by CSS, and each tab on a piece of torn paper.
import type { Locator } from '@playwright/test';
import { expect, expectAccessible, test } from './fixtures';

const BLUE = 'rgb(11, 91, 211)';
const SKY = 'rgb(207, 225, 250)';
const NAVY = 'rgb(15, 31, 61)';

/** The color of the torn paper an element is on: its border image is drawn in it. */
const paper = (element: Locator) =>
  element.evaluate((el) => getComputedStyle(el).borderImageSource.match(/%23([0-9a-f]{6})/)?.[1]);

test('selected things are FABA blue, and the bar keeps its five items', async ({
  page,
  signInAs,
}) => {
  await signInAs('member');
  await page.goto('/discover');

  const bar = page.getByRole('navigation', { name: 'Main' });
  await expect(bar.getByRole('link')).toHaveText(['Discover', 'Plans', 'Post', /^Alerts/, 'Me']);
  await expect(bar.locator('svg')).toHaveCount(5);
  // The current tab's tile is light blue, and it's underlined, so it isn't color alone.
  const here = bar.getByRole('link', { name: 'Discover' });
  await expect(here).toHaveAttribute('aria-current', 'page');
  await expect(here.locator('.tile')).toHaveCSS('background-color', SKY);
  await expect(bar.getByRole('link', { name: 'Plans' }).locator('.tile')).toHaveCSS(
    'background-color',
    'rgb(255, 255, 255)'
  );
  // Post is a navy square that rises above the bar (UI-14).
  await expect(bar.locator('.post .square')).toHaveCSS('background-color', NAVY);

  // Activities is on FABA blue paper, and Groups on light blue.
  const halves = page.getByRole('navigation', { name: 'Discover' });
  expect(await paper(halves.getByRole('link', { name: 'Activities' }))).toBe('0b5bd3');
  expect(await paper(halves.getByRole('link', { name: 'Groups' }))).toBe('cfe1fa');
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

test("Discover's heading is big, in Anton and in capitals, but still says Discover", async ({
  page,
  signInAs,
}) => {
  await signInAs('member');
  await page.goto('/discover');
  const heading = page.getByRole('heading', { level: 1 });
  // Capitals come from CSS, so the page, screen readers and search keep the word as written.
  await expect(heading).toHaveText('Discover');
  await expect(heading).toHaveCSS('text-transform', 'uppercase');
  await expect(heading).toHaveCSS('font-family', /^Anton/);
  expect(await page.evaluate(() => document.fonts.check('48px Anton'))).toBe(true);
  // On one line at every width, and as big as a heading on a phone should be.
  const size = parseFloat(await heading.evaluate((el) => getComputedStyle(el).fontSize));
  expect(size).toBeGreaterThanOrEqual(44);
  expect((await heading.boundingBox())!.height).toBeLessThan(size * 1.6);
  // It sits on its own strip of torn white paper, and the page's content on a paper sheet.
  expect(await paper(heading)).toBe('ffffff');
  expect(await paper(page.locator('main'))).toBe('f7f4ec');
  expect(await page.evaluate(() => document.documentElement.scrollWidth <= window.innerWidth)).toBe(
    true
  );
  await expectAccessible(page);
});

test('in high contrast, the paper gives way to plain borders', async ({ page, signInAs }) => {
  await signInAs('member');
  await page.emulateMedia({ forcedColors: 'active' });
  await page.goto('/discover');
  for (const piece of [
    page.locator('main'),
    page.getByRole('heading', { level: 1 }),
    page.getByRole('navigation', { name: 'Discover' }).getByRole('link', { name: 'Groups' }),
  ]) {
    await expect(piece).toHaveCSS('border-image-source', 'none');
    await expect(piece).not.toHaveCSS('border-left-color', /rgba\(0, 0, 0, 0\)/);
  }
  await expect(page.locator('html')).toHaveCSS('background-image', 'none');
});

test('the motto is beside the logo, on the public pages too', async ({ page }) => {
  for (const path of ['/about', '/guidelines']) {
    await page.goto(path);
    const header = page.locator('header.site');
    const motto = header.getByText('Bringing faculty together!', { exact: true });
    await expect(motto).toBeVisible();
    // To the right of the mark and FABA, and not part of the link, whose name stays FABA.
    const brand = header.getByRole('link', { name: 'FABA', exact: true });
    const [link, words] = [(await brand.boundingBox())!, (await motto.boundingBox())!];
    expect(words.x).toBeGreaterThanOrEqual(link.x + link.width);
    expect(words.x + words.width).toBeLessThanOrEqual(page.viewportSize()!.width);
    // Two lines on a narrow phone are no taller than the logo's link.
    expect(words.height).toBeLessThanOrEqual(link.height);
    expect(
      await page.evaluate(() => document.documentElement.scrollWidth <= window.innerWidth)
    ).toBe(true);
  }
  await expectAccessible(page);
});
