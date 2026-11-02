// Discover and Welcome for signed-in personas, and signing out (FND-10, AUTH-01).
import { expect, expectAccessible, test } from './fixtures';

test('a member sees upcoming activities and can sign out', async ({ page, signInAs }) => {
  await signInAs('member');
  await page.goto('/discover');
  await expect(page.getByText('Signed in as Maya Member.')).toBeVisible();
  await expect(page.getByRole('heading', { name: 'Coming up' })).toBeVisible();
  await expect(page.getByRole('listitem')).not.toHaveCount(0);
  await expectAccessible(page);

  await page.getByRole('button', { name: 'Sign out' }).click();
  await expect(page).toHaveURL('/');
  await expect(page.getByRole('button', { name: 'Continue with Google' })).toBeVisible();

  // The session is gone, so Discover asks for sign-in again.
  await page.goto('/discover');
  await expect(page).toHaveURL('/auth/login?next=%2Fdiscover');
});

test('a suspended member sees no activities', async ({ page, signInAs }) => {
  await signInAs('suspended');
  await page.goto('/discover');
  await expect(page.getByText('Signed in as Sam Suspended.')).toBeVisible();
  await expect(page.getByText('No activities yet.')).toBeVisible();
  await expectAccessible(page);
});

test('members who have accepted the guidelines skip Welcome', async ({ page, signInAs }) => {
  await signInAs('member');
  await page.goto('/welcome?next=%2Fdiscover%3Fcat%3Dhiking');
  await expect(page).toHaveURL('/discover?cat=hiking');

  await page.goto('/me');
  await expect(page.getByRole('heading', { level: 1, name: 'Me' })).toBeVisible();
  await expectAccessible(page);
});
