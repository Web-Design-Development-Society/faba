// Installing FABA on the home screen, and the offline state (PWA-01, design document section 7.13).
import { expect, test } from './fixtures';

test('FABA has a manifest and icons so it can be installed', async ({ page, request }) => {
  await page.goto('/');
  await expect(page.locator('link[rel="manifest"]')).toHaveAttribute(
    'href',
    '/manifest.webmanifest'
  );

  const manifest = await (await request.get('/manifest.webmanifest')).json();
  expect(manifest.name).toBe('FABA');
  expect(manifest.display).toBe('standalone');
  for (const icon of manifest.icons) {
    expect((await request.get(icon.src)).status(), icon.src).toBe(200);
  }

  const offline = await request.get('/offline.html');
  expect(offline.status()).toBe(200);
  expect(await offline.text()).toContain("You're offline");
});

test('offline shows a banner and stops forms from being sent', async ({
  page,
  context,
  signInAs,
}) => {
  await signInAs('member');
  await page.goto('/me');
  const banner = page.getByText("You're offline. We'll keep what you typed.");
  const signOut = page.getByRole('button', { name: 'Sign out' });
  await expect(banner).toBeHidden();
  await expect(signOut).toBeEnabled();

  await context.setOffline(true);
  await expect(banner).toBeVisible();
  await expect(signOut).toBeDisabled();

  await context.setOffline(false);
  await expect(banner).toBeHidden();
  await expect(signOut).toBeEnabled();
});
