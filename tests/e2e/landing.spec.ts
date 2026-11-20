// The landing page (UI-37): the big logo with its high five, the motto, what FABA is, and
// Continue with Google. signed-out.spec.ts covers signing in from it.
import type { Page } from '@playwright/test';
import { expect, expectAccessible, test } from './fixtures';

/** The logo's animations, by name, with how many times each runs. */
const animations = (page: Page) =>
  page.evaluate(() =>
    document
      .getAnimations()
      .map((a) => ({
        name: (a as CSSAnimation).animationName,
        iterations: a.effect?.getTiming().iterations,
      }))
      .sort((x, y) => x.name.localeCompare(y.name))
  );

test('the landing page shows the big logo, says what FABA is, and offers sign-in', async ({
  page,
}) => {
  await page.goto('/');

  // Continue with Google is there from the start, while the logo is still moving.
  await expect(page.getByRole('button', { name: 'Continue with Google' })).toBeVisible();

  // The logo is the heading, in the middle at the top, in place of the header strip.
  const logo = page.getByRole('heading', { level: 1, name: 'FABA' });
  await expect(logo).toBeVisible();
  await expect(page.getByRole('banner')).toHaveCount(0);
  const box = (await logo.boundingBox())!;
  const width = page.viewportSize()!.width;
  expect(Math.abs(box.x + box.width / 2 - width / 2)).toBeLessThan(1);
  expect(box.width).toBeCloseTo(200, 0);
  for (const person of await logo.locator('img').all()) {
    expect(await person.evaluate((img: HTMLImageElement) => img.naturalWidth)).toBe(312);
  }
  await expect(logo.locator('.wordmark')).toHaveCSS('background-color', 'rgb(15, 31, 61)');
  await expect(page.getByText('Bringing faculty together!')).toBeVisible();

  // What FABA is, in a sentence and three points.
  await expect(
    page.getByText('FABA helps BYU-Idaho faculty find each other outside work.')
  ).toBeVisible();
  await expect(page.getByRole('main').getByRole('listitem')).toHaveText([
    /^Find something to do:/,
    /^Say I'm in and see who else is going\.$/,
    /^Post your own activity/,
  ]);
  await expect(page.getByRole('link', { name: 'What is FABA?' })).toHaveAttribute('href', '/about');

  // The high five runs once: each person swings in, and the lines flash, then they settle into the
  // logo and the lines are gone.
  expect(await animations(page)).toEqual([
    { name: 'high-five-left', iterations: 1 },
    { name: 'high-five-right', iterations: 1 },
    { name: 'high-five-spark', iterations: 1 },
  ]);
  await page.evaluate(() => Promise.all(document.getAnimations().map((a) => a.finished)));
  for (const person of await logo.locator('img').all()) {
    // Where the logo has them: no move, though the browser may say so as a matrix.
    await expect(person).toHaveCSS('transform', /^(none|matrix\(1, 0, 0, 1, 0, 0\))$/);
    await expect(person).toHaveCSS('opacity', '1');
  }
  await expect(logo.locator('.spark')).toHaveCSS('opacity', '0');
  await expectAccessible(page);
});

test.describe('with Reduce motion on', () => {
  test.use({ reducedMotion: 'reduce' });

  test('the logo is simply there', async ({ page }) => {
    await page.goto('/');
    expect(await animations(page)).toEqual([]);
    for (const person of await page.locator('.person').all()) {
      await expect(person).toHaveCSS('opacity', '1');
      await expect(person).toHaveCSS('transform', 'none');
    }
  });
});

test.describe('in the dark', () => {
  test.use({ colorScheme: 'dark' });

  test('the wordmark is soft white, and the page is readable', async ({ page }) => {
    await page.goto('/');
    await expect(page.locator('.wordmark')).toHaveCSS('background-color', 'rgb(238, 242, 248)');
    await expectAccessible(page);
  });
});
