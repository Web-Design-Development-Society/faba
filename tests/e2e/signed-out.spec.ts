// What visitors see before signing in (design document section 9.7, AUTH-01).
import type { Page } from '@playwright/test';
import { expect, expectAccessible, SUPABASE_PUBLISHABLE_KEY, SUPABASE_URL, test } from './fixtures';

/**
 * Catches FABA's redirect to Supabase instead of following it to Google. Playwright can't route
 * the requests a redirect makes, so this stops at the form post. Returns where it was going.
 */
async function catchSignInRedirect(page: Page) {
  const caught: { url?: URL } = {};
  await page.route(
    (url) => url.pathname === '/auth/login',
    async (route) => {
      if (route.request().method() !== 'POST') return route.fallback();
      const response = await route.fetch({ maxRedirects: 0 });
      expect(response.status()).toBe(303);
      caught.url = new URL(response.headers().location);
      await route.fulfill({ body: 'Supabase would send you to Google now.' });
    }
  );
  return caught;
}

test('the landing page offers Google sign-in', async ({ page }) => {
  await page.goto('/');
  await expect(page.getByRole('heading', { level: 1, name: 'FABA' })).toBeVisible();
  // The only way in (AUTH-01).
  await expect(page.getByRole('button')).toHaveText(['Continue with Google']);
  await expect(page.getByRole('heading', { name: 'Open in your browser' })).toBeHidden();
  await expectAccessible(page);
});

test('Discover sends visitors to sign in and back', async ({ page }) => {
  await page.goto('/discover');
  await expect(page).toHaveURL('/auth/login?next=%2Fdiscover');
  await expect(page.getByRole('heading', { level: 1, name: 'Sign in to FABA' })).toBeVisible();
  await expectAccessible(page);
});

test('signing in starts Google sign-in through Supabase', async ({ page, context, baseURL }) => {
  const caught = await catchSignInRedirect(page);
  await page.goto('/auth/login?next=%2Fdiscover');
  await page.getByRole('button', { name: 'Continue with Google' }).click();
  await expect(page.getByText('Supabase would send you to Google now.')).toBeVisible();

  const redirect = caught.url;
  expect(redirect?.origin).toBe(SUPABASE_URL);
  expect(redirect?.pathname).toBe('/auth/v1/authorize');
  expect(redirect?.searchParams.get('provider')).toBe('google');
  expect(redirect?.searchParams.get('redirect_to')).toBe(new URL('/auth/callback', baseURL).href);
  // PKCE, and what Supabase passes on to Google. It adds openid to email and profile.
  expect(redirect?.searchParams.get('code_challenge_method')).toBe('s256');
  expect(redirect?.searchParams.get('code_challenge')).toBeTruthy();
  expect(redirect?.searchParams.get('scopes')).toBe('openid');
  expect(redirect?.searchParams.get('hd')).toBe('byui.edu');
  expect(redirect?.searchParams.get('prompt')).toBe('select_account');

  // The callback returns to Discover afterwards. Page scripts can't read any of the cookies.
  // They're Secure too, except on plain-HTTP localhost.
  const cookies = await context.cookies(new URL('/auth/callback', baseURL).href);
  expect(cookies.find(({ name }) => name === 'faba-next')?.value).toBe('/discover');
  expect(cookies.find(({ name }) => name.endsWith('-code-verifier'))).toBeDefined();
  for (const cookie of cookies) {
    expect(cookie).toMatchObject({ httpOnly: true, sameSite: 'Lax' });
  }
});

test('cancelling at Google comes back to the landing page to try again', async ({
  page,
  context,
  baseURL,
}) => {
  // As if sign-in started from a link to an activity.
  await context.addCookies([
    {
      name: 'faba-next',
      value: '/activities/42',
      domain: new URL(baseURL!).hostname,
      path: '/auth',
    },
  ]);
  await page.goto('/auth/callback?error=access_denied&error_description=The+user+denied+access');
  await expect(page).toHaveURL('/?error=cancelled&next=%2Factivities%2F42');
  await expect(page.getByRole('alert')).toHaveText(
    "You didn't finish signing in with Google. Try again when you're ready."
  );
  await expect(page.getByRole('button')).toHaveText(['Try again']);
  await expectAccessible(page);

  const caught = await catchSignInRedirect(page);
  await page.getByRole('button', { name: 'Try again' }).click();
  await expect(page.getByText('Supabase would send you to Google now.')).toBeVisible();
  expect(caught.url?.pathname).toBe('/auth/v1/authorize');
  const cookies = await context.cookies(new URL('/auth/callback', baseURL).href);
  expect(cookies.find(({ name }) => name === 'faba-next')?.value).toBe('/activities/42');
});

test('a sign-in error comes back to the landing page', async ({ page }) => {
  await page.goto('/auth/callback?error=server_error');
  await expect(page).toHaveURL('/?error=failed');
  await expect(page.getByRole('alert')).toHaveText(
    "Google sign-in didn't work this time. Please try again."
  );
  await expect(page.getByRole('button', { name: 'Try again' })).toBeVisible();
});

test.describe("in an app's built-in browser", () => {
  test.use({
    userAgent:
      'Mozilla/5.0 (iPhone; CPU iPhone OS 18_1 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Mobile/15E148 Instagram 357.0.0.25.101',
  });

  test('the landing page suggests opening it in the browser', async ({ page }) => {
    await page.goto('/');
    await expect(page.getByRole('heading', { name: 'Open in your browser' })).toBeVisible();
    await expect(page.getByRole('button', { name: 'Continue with Google' })).toBeVisible();
    await expectAccessible(page);
  });
});

test('the not-eligible page explains who can join', async ({ page }) => {
  await page.goto('/not-eligible');
  await expect(
    page.getByRole('heading', { level: 1, name: 'FABA is for BYU-Idaho faculty' })
  ).toBeVisible();
  await expect(page.getByText('Only byui.edu Google accounts can join.')).toBeVisible();
  await expect(page.getByText("isn't an official BYU-Idaho site, so it can't make")).toBeVisible();
  await expectAccessible(page);

  // Google shows its account chooser again (prompt=select_account).
  const caught = await catchSignInRedirect(page);
  await page.getByRole('button', { name: 'Try a different account' }).click();
  await expect(page.getByText('Supabase would send you to Google now.')).toBeVisible();
  expect(caught.url?.searchParams.get('prompt')).toBe('select_account');
});

test("Supabase Auth refuses to create an account that isn't byui.edu", async ({
  request,
}, testInfo) => {
  test.skip(testInfo.project.name !== 'desktop', 'No browser involved, so once is enough.');
  // Signing up with a password runs the same before-user-created hook as Google sign-in (ADR-005).
  const account = { email: 'not-eligible.test@example.com', password: 'faba-local-dev' };
  const headers = { apikey: SUPABASE_PUBLISHABLE_KEY };
  const signUp = await request.post(`${SUPABASE_URL}/auth/v1/signup`, { headers, data: account });
  expect(signUp.status()).toBe(403);
  expect((await signUp.json()).msg).toBe(
    'FABA is for BYU-Idaho. Sign in with your byui.edu account.'
  );

  // No account was created, so it can't sign in.
  const signIn = await request.post(`${SUPABASE_URL}/auth/v1/token?grant_type=password`, {
    headers,
    data: account,
  });
  expect((await signIn.json()).error_code).toBe('invalid_credentials');
});
