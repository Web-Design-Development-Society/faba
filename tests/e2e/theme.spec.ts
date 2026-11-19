// Choosing light or dark on Me (UI-34): Match device follows the device (UI-33), and Light or Dark
// wins over it, on every page of this device, with exactly the same colors.
import type { Page } from '@playwright/test';
import { expect, expectAccessible, test } from './fixtures';

const LIGHT_PAGE = 'rgb(244, 246, 248)';
const DARK_PAGE = 'rgb(15, 20, 27)';

/** Every token the root sets, such as --page, with its value as the page has it now. */
const tokens = (page: Page) =>
  page.evaluate(() => {
    const names = new Set<string>();
    const collect = (rules: CSSRuleList) => {
      for (const rule of rules) {
        if (rule instanceof CSSStyleRule && rule.selectorText.startsWith(':root')) {
          for (const name of rule.style) if (name.startsWith('--')) names.add(name);
        } else if ('cssRules' in rule) {
          collect((rule as CSSGroupingRule).cssRules);
        }
      }
    };
    for (const sheet of document.styleSheets) collect(sheet.cssRules);
    const style = getComputedStyle(document.documentElement);
    return Object.fromEntries(
      [...names].sort().map((name) => [name, style.getPropertyValue(name)])
    );
  });

const themeCard = (page: Page) => page.getByRole('region', { name: 'Theme' });

test('Light or Dark wins over the device, with the same colors, and Match device follows it again', async ({
  page,
  signInAs,
}) => {
  await signInAs('member');
  await page.goto('/me');
  const html = page.locator('html');
  const choices = page.getByRole('group', { name: 'Theme' });
  // Match device until another is chosen, and the page follows the device.
  await expect(choices.getByLabel('Match device')).toBeChecked();
  await expect(html).not.toHaveAttribute('data-theme');
  await expect(html).toHaveCSS('background-color', LIGHT_PAGE);
  // With JavaScript, a choice saves at once, so there's no Save.
  await expect(themeCard(page).getByRole('button', { name: 'Save' })).toBeHidden();
  const light = await tokens(page);
  await page.emulateMedia({ colorScheme: 'dark' });
  await expect(html).toHaveCSS('background-color', DARK_PAGE);
  const dark = await tokens(page);
  expect(dark['--page']).toBe('#0f141b');
  expect(Object.keys(dark).length).toBeGreaterThan(30);

  // Light on a dark device: the light theme's very colors, and the browser's parts light too.
  await choices.getByText('Light', { exact: true }).click();
  await expect(page.getByRole('status')).toHaveText('Theme saved.');
  await expect(page).toHaveURL('/me#theme');
  await expect(html).toHaveAttribute('data-theme', 'light');
  await expect(choices.getByLabel('Light')).toBeChecked();
  expect(await tokens(page)).toEqual(light);
  await expect(html).toHaveCSS('color-scheme', 'light');
  await expect(page.locator('meta[name="theme-color"]')).toHaveCount(1);
  await expect(page.locator('meta[name="theme-color"]')).toHaveAttribute('content', '#f4f7fb');
  await expect(page.locator('meta[name="color-scheme"]')).toHaveAttribute('content', 'light');
  await expectAccessible(page);

  // Dark on a light device: the dark theme's very colors, on every page, after a reload too.
  await page.emulateMedia({ colorScheme: 'light' });
  await choices.getByText('Dark', { exact: true }).click();
  await expect(page.getByRole('status')).toHaveText('Theme saved.');
  await expect(html).toHaveAttribute('data-theme', 'dark');
  await expect(choices.getByLabel('Dark')).toBeChecked();
  expect(await tokens(page)).toEqual(dark);
  await expect(html).toHaveCSS('background-color', DARK_PAGE);
  await expect(html).toHaveCSS('color-scheme', 'dark');
  await expect(page.locator('meta[name="theme-color"]')).toHaveAttribute('content', '#0f141b');
  await expect(page.locator('meta[name="color-scheme"]')).toHaveAttribute('content', 'dark');
  await expectAccessible(page);
  for (const path of ['/discover', '/activities/new']) {
    await page.goto(path);
    await expect(html, path).toHaveAttribute('data-theme', 'dark');
    await expect(html, path).toHaveCSS('background-color', DARK_PAGE);
  }
  await page.reload();
  await expect(html).toHaveCSS('background-color', DARK_PAGE);

  // Match device follows the device again, and the choice is gone from it.
  await page.goto('/me');
  await choices.getByText('Match device').click();
  await expect(page.getByRole('status')).toHaveText('Theme saved.');
  await expect(html).not.toHaveAttribute('data-theme');
  await expect(html).toHaveCSS('background-color', LIGHT_PAGE);
  await page.emulateMedia({ colorScheme: 'dark' });
  await expect(html).toHaveCSS('background-color', DARK_PAGE);
  await expect(page.locator('meta[name="theme-color"]')).toHaveCount(2);
  const cookies = await page.context().cookies();
  expect(cookies.map(({ name }) => name)).not.toContain('faba-theme');
});

test('the choice lasts on the device after signing out, but not on the prerendered pages', async ({
  page,
  baseURL,
}) => {
  await page.context().addCookies([{ name: 'faba-theme', value: 'dark', url: baseURL! }]);
  for (const path of ['/', '/auth/login']) {
    await page.goto(path);
    await expect(page.locator('html'), path).toHaveCSS('background-color', DARK_PAGE);
  }
  // About is drawn once, when FABA is built, so it follows the device (ADR-001).
  await page.goto('/about');
  await expect(page.locator('html')).not.toHaveAttribute('data-theme');
  await expect(page.locator('html')).toHaveCSS('background-color', LIGHT_PAGE);
  // Anything else in the cookie follows the device.
  await page.context().addCookies([{ name: 'faba-theme', value: 'purple', url: baseURL! }]);
  await page.goto('/');
  await expect(page.locator('html')).not.toHaveAttribute('data-theme');
});

test.describe('without JavaScript', () => {
  test.use({ javaScriptEnabled: false });

  test('Save sends the choice', async ({ page, signInAs }) => {
    await signInAs('member');
    await page.goto('/me');
    const card = themeCard(page);
    await card.getByText('Dark', { exact: true }).click();
    await card.getByRole('button', { name: 'Save' }).click();
    await expect(page.getByRole('status')).toHaveText('Theme saved.');
    await expect(page.locator('html')).toHaveAttribute('data-theme', 'dark');
    await expect(page.locator('html')).toHaveCSS('background-color', DARK_PAGE);
    await expect(card.getByLabel('Dark')).toBeChecked();
  });
});
