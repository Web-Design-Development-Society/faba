// Adding FABA to the home screen (UI-31): a card on Me, under the calendar feed, with a sheet of
// steps for iPhone and one for Android, each from the phone maker's own page.
import { expect, expectAccessible, test } from './fixtures';

test('Me shows how to add FABA to the home screen, on iPhone and on Android', async ({
  page,
  signInAs,
}) => {
  await signInAs('member');
  await page.goto('/me');
  const card = page.getByRole('region', { name: 'Add FABA to your home screen' });
  await expect(card).toBeVisible();
  // Under the calendar feed.
  const feed = page.getByRole('region', { name: 'Calendar feed' });
  expect((await card.boundingBox())!.y).toBeGreaterThan((await feed.boundingBox())!.y);

  await card.getByRole('button', { name: 'On iPhone' }).click();
  const iphone = page.getByRole('dialog', { name: 'Add FABA on iPhone' });
  await expect(iphone.getByRole('listitem')).toHaveCount(5);
  await expect(iphone.getByRole('listitem').nth(3)).toHaveText('Turn on Open as Web App.');
  await expect(iphone.getByRole('link', { name: "Apple's steps" })).toHaveAttribute(
    'href',
    'https://support.apple.com/guide/iphone/open-as-web-app-iphea86e5236/ios'
  );
  // The title keeps iPhone's small i.
  await expect(iphone.getByRole('heading')).toHaveCSS('text-transform', 'none');
  await expectAccessible(page);
  await iphone.getByRole('button', { name: 'Close' }).click();
  await expect(iphone).toBeHidden();

  await card.getByRole('button', { name: 'On Android' }).click();
  const android = page.getByRole('dialog', { name: 'Add FABA on Android' });
  await expect(android.getByRole('listitem')).toHaveCount(4);
  await expect(android.getByRole('listitem').nth(2)).toHaveText(
    'Tap Install and create shortcut, then Install.'
  );
  await expect(android.getByRole('link', { name: "Google's steps" })).toHaveAttribute(
    'href',
    /^https:\/\/support\.google\.com\/chrome\/answer\/9658361/
  );
  expect(await page.evaluate(() => document.documentElement.scrollWidth <= window.innerWidth)).toBe(
    true
  );
});

test('opened from the home screen, Me leaves the card out', async ({ page, signInAs }) => {
  await signInAs('member');
  await page.goto('/me');
  // No browser in the tests can run as an installed app, and Chromium can't pretend to for
  // display-mode, so this checks the page's own rule: in standalone mode, the card isn't shown.
  const hidden = await page.evaluate(() => {
    const card = document.getElementById('home-screen')!;
    for (const sheet of document.styleSheets) {
      for (const rule of sheet.cssRules) {
        if (!(rule instanceof CSSMediaRule)) continue;
        if (!rule.conditionText.includes('display-mode: standalone')) continue;
        for (const inner of rule.cssRules) {
          if (inner instanceof CSSStyleRule && card.matches(inner.selectorText)) {
            return inner.style.display;
          }
        }
      }
    }
    return null;
  });
  expect(hidden).toBe('none');
  // In a browser tab, it's there.
  await expect(page.getByRole('region', { name: 'Add FABA to your home screen' })).toBeVisible();
});

test.describe('without JavaScript', () => {
  test.use({ javaScriptEnabled: false });

  test('the steps still open', async ({ page, signInAs }) => {
    await signInAs('member');
    await page.goto('/me');
    await page.getByRole('button', { name: 'On Android' }).click();
    await expect(page.getByRole('dialog', { name: 'Add FABA on Android' })).toBeVisible();
  });
});
