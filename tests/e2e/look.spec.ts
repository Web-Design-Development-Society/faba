// FABA's look (UI-02, UI-14, UI-16): the bottom bar keeps its five items, each with a line icon in
// a tile over its label, and the current tab and chosen date are FABA blue. The cut-paper look puts
// headings in Anton, in capitals by CSS, and each tab on a piece of paper with square corners and a
// shadow, over a photo of torn paper.
import type { Locator } from '@playwright/test';
import { expect, expectAccessible, expectSquare, paper, test } from './fixtures';

const BLUE = 'rgb(11, 91, 211)';
const SKY = 'rgb(207, 225, 250)';
const NAVY = 'rgb(15, 31, 61)';

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
  // It sits on its own strip of white paper, and the page's content on a paper sheet, each with
  // square corners and a shadow, over the photo of torn paper (UI-16).
  expect(await paper(heading)).toBe('ffffff');
  expect(await paper(page.locator('main'))).toBe('f7f4ec');
  await expectSquare(heading);
  await expectSquare(page.locator('main'));
  expect(
    await page.evaluate(
      () => getComputedStyle(document.documentElement, '::before').backgroundImage
    )
  ).toMatch(/\/backgrounds\/torn-paper\.webp/);
  expect(await page.evaluate(() => document.documentElement.scrollWidth <= window.innerWidth)).toBe(
    true
  );
  await expectAccessible(page);
});

test('in high contrast, the paper gives way to plain borders', async ({ page, poster, host }) => {
  // An unread alert, for its card on Alerts (UI-15).
  const id = await host.post();
  await poster.admin
    .from('notifications')
    .insert({ recipient_id: poster.id, type: 'rsvp_confirmed', activity_id: id, payload: {} });
  await page.emulateMedia({ forcedColors: 'active' });
  await page.goto('/discover');
  const plain = async (piece: Locator) => {
    await expect(piece).toHaveCSS('box-shadow', 'none');
    await expect(piece).not.toHaveCSS('border-left-color', /rgba\(0, 0, 0, 0\)/);
  };
  await plain(page.locator('main'));
  await plain(page.getByRole('heading', { level: 1 }));
  await plain(
    page.getByRole('navigation', { name: 'Discover' }).getByRole('link', { name: 'Groups' })
  );
  // No photo behind the page.
  await expect(page.locator('html')).toHaveCSS('background-image', 'none');
  expect(
    await page.evaluate(() => getComputedStyle(document.documentElement, '::before').display)
  ).toBe('none');

  // An alert's card too, and its unread dot still shows.
  await page.goto('/notifications');
  const card = page.getByRole('region', { name: 'New' }).getByRole('button');
  await plain(card);
  await expect(card).toHaveCSS('background-image', 'none');
  const dot = await card.getByText('Sunrise hike up the R').evaluate((el) => {
    const { content, borderTopColor, borderTopWidth } = getComputedStyle(el, '::before');
    return { content, borderTopColor, borderTopWidth };
  });
  expect(dot.content).not.toBe('none');
  expect(dot.borderTopColor).not.toMatch(/rgba\(0, 0, 0, 0\)/);
  expect(parseFloat(dot.borderTopWidth)).toBeGreaterThan(0);
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
