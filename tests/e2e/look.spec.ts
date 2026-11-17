// FABA's look (UI-02, UI-14, UI-16): the bottom bar keeps its five items, each with a line icon in
// a tile over its label, and the current tab and chosen date are FABA blue. The cut-paper look puts
// headings in Anton, in capitals by CSS, and each tab on a piece of paper with square corners and a
// shadow, over a faded photo of torn paper that text sits straight on.
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
  // It sits on its own strip of white paper, with square corners and a shadow (UI-16). The page's
  // content has no sheet: it sits straight on a faded photo of torn paper.
  expect(await paper(heading)).toBe('ffffff');
  await expectSquare(heading);
  const main = page.locator('main');
  await expect(main).toHaveCSS('background-color', 'rgba(0, 0, 0, 0)');
  await expect(main).toHaveCSS('box-shadow', 'none');
  expect(
    await page.evaluate(
      () => getComputedStyle(document.documentElement, '::before').backgroundImage
    )
  ).toMatch(/\/backgrounds\/torn-paper-faded\.webp/);
  // The color under the photo is no lighter than its darkest patch, so the accessibility check,
  // which can't see the photo, measures text against the worst place it could sit. A patch is 4 by
  // 4 pixels, about the size of a letter's stroke, averaged here rather than by the browser's own
  // scaling, which differs between browsers.
  const [darkest, under] = await page.evaluate(async () => {
    const channel = (c: number) =>
      c / 255 <= 0.04045 ? c / 255 / 12.92 : ((c / 255 + 0.055) / 1.055) ** 2.4;
    const luminance = (r: number, g: number, b: number) =>
      0.2126 * channel(r) + 0.7152 * channel(g) + 0.0722 * channel(b);
    const image = new Image();
    image.src = '/backgrounds/torn-paper-faded.webp';
    await image.decode();
    const { naturalWidth: width, naturalHeight: height } = image;
    const canvas = Object.assign(document.createElement('canvas'), { width, height });
    const context = canvas.getContext('2d', { willReadFrequently: true })!;
    context.drawImage(image, 0, 0);
    const { data } = context.getImageData(0, 0, width, height);
    let least = 1;
    for (let y = 0; y + 4 <= height; y += 4) {
      for (let x = 0; x + 4 <= width; x += 4) {
        const sum = [0, 0, 0];
        for (let row = y; row < y + 4; row++) {
          for (let column = x; column < x + 4; column++) {
            for (let part = 0; part < 3; part++)
              sum[part] += data[(row * width + column) * 4 + part];
          }
        }
        least = Math.min(least, luminance(sum[0] / 16, sum[1] / 16, sum[2] / 16));
      }
    }
    const [r, g, b] = getComputedStyle(document.documentElement)
      .backgroundColor.match(/\d+/g)!
      .map(Number);
    return [least, luminance(r, g, b)];
  });
  // A little room for each browser decoding the photo slightly differently.
  expect(darkest).toBeGreaterThanOrEqual(under - 0.003);
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
  await plain(page.getByRole('heading', { level: 1 }));
  await plain(
    page.getByRole('navigation', { name: 'Discover' }).getByRole('link', { name: 'Groups' })
  );
  // An activity card's blue column is plain, with a line between it and the rest (UI-17).
  const side = page.getByRole('article').first().locator('.side');
  await expect(side).toHaveCSS('box-shadow', 'none');
  await expect(side).toHaveCSS('border-left-style', 'solid');
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
