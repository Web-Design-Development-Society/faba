// What visitors see before signing in (design document section 9.7).
import { expect, expectAccessible, SUPABASE_URL, test } from './fixtures';

test('the landing page offers Google sign-in', async ({ page }) => {
  await page.goto('/');
  await expect(page.getByRole('heading', { level: 1, name: 'FABA' })).toBeVisible();
  await expect(page.getByRole('button', { name: 'Continue with Google' })).toBeVisible();
  await expectAccessible(page);
});

test('Discover sends visitors to sign in and back', async ({ page }) => {
  await page.goto('/discover');
  await expect(page).toHaveURL('/auth/login?next=%2Fdiscover');
  await expect(page.getByRole('heading', { level: 1, name: 'Sign in to FABA' })).toBeVisible();
  await expectAccessible(page);
});

test('signing in starts Google sign-in through Supabase', async ({ page, context, baseURL }) => {
  // Catch FABA's redirect instead of following it through Supabase to Google. Playwright can't
  // route the requests a redirect makes, so this stops at the form post.
  let redirect: URL | undefined;
  await page.route(
    (url) => url.pathname === '/auth/login',
    async (route) => {
      if (route.request().method() !== 'POST') return route.fallback();
      const response = await route.fetch({ maxRedirects: 0 });
      expect(response.status()).toBe(303);
      redirect = new URL(response.headers().location);
      await route.fulfill({ body: 'Supabase would send you to Google now.' });
    }
  );

  await page.goto('/auth/login?next=%2Fdiscover');
  await page.getByRole('button', { name: 'Continue with Google' }).click();
  await expect(page.getByText('Supabase would send you to Google now.')).toBeVisible();

  expect(redirect?.origin).toBe(SUPABASE_URL);
  expect(redirect?.pathname).toBe('/auth/v1/authorize');
  expect(redirect?.searchParams.get('provider')).toBe('google');
  expect(redirect?.searchParams.get('redirect_to')).toBe(new URL('/auth/callback', baseURL).href);
  // The callback returns to Discover afterwards.
  const cookies = await context.cookies(new URL('/auth/callback', baseURL).href);
  expect(cookies.find(({ name }) => name === 'faba-next')?.value).toBe('/discover');
});

test('the not-eligible page explains who can join', async ({ page }) => {
  await page.goto('/not-eligible');
  await expect(
    page.getByRole('heading', { level: 1, name: 'FABA is for BYU-Idaho faculty' })
  ).toBeVisible();
  await expect(page.getByRole('button', { name: 'Try a different account' })).toBeVisible();
  await expectAccessible(page);
});
