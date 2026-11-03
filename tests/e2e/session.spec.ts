// Staying signed in, and signing out (AUTH-03).
import type { Session } from '@supabase/supabase-js';
import { expect, readSession, sessionCookies, test, writeSession } from './fixtures';

/** `session` as if its access token had run out a minute ago, so the next request refreshes it. */
function expired(session: Session): Session {
  return { ...session, expires_at: Math.floor(Date.now() / 1000) - 60 };
}

test('an expired session refreshes without asking to sign in again', async ({
  page,
  context,
  baseURL,
  signInAs,
}) => {
  await signInAs('member');
  const session = await readSession(context, baseURL!);
  await writeSession(context, baseURL!, expired(session));

  await page.goto('/me');
  await expect(page.getByText("You're signed in as Maya Member.")).toBeVisible();

  // The middleware swapped the refresh token for a new one and saved the new session.
  const refreshed = await readSession(context, baseURL!);
  expect(refreshed.refresh_token).not.toBe(session.refresh_token);
  expect(refreshed.expires_at).toBeGreaterThan(Date.now() / 1000);
});

test('signing out on Me ends the session', async ({ page, context, baseURL, signInAs }) => {
  await signInAs('member');
  await page.goto('/discover');
  await page.getByRole('link', { name: 'Me' }).click();
  await expect(page).toHaveURL('/me');
  const session = await readSession(context, baseURL!);

  await page.getByRole('button', { name: 'Sign out' }).click();
  await expect(page).toHaveURL('/');
  await expect(page.getByRole('button', { name: 'Continue with Google' })).toBeVisible();
  expect(await sessionCookies(context, baseURL!)).toEqual([]);

  // Supabase ended the session too, so a copy of the old cookies can't refresh it.
  await writeSession(context, baseURL!, expired(session));
  await page.goto('/discover');
  await expect(page).toHaveURL('/auth/login?next=%2Fdiscover');
});

test("after signing out, Back doesn't show private pages", async ({ page, signInAs }) => {
  await signInAs('member');
  const response = await page.goto('/me');
  expect(response?.headers()['cache-control']).toBe('private, no-store');
  await expect(page.getByText("You're signed in as Maya Member.")).toBeVisible();

  await page.getByRole('button', { name: 'Sign out' }).click();
  await expect(page).toHaveURL('/');
  await page.goBack();
  await expect(page).toHaveURL('/auth/login?next=%2Fme');
  await expect(page.getByText("You're signed in as")).toHaveCount(0);
});
