// Discover and Welcome for signed-in personas (FND-10, PROF-01). session.spec.ts covers signing
// out.
import { expect, expectAccessible, test } from './fixtures';

test('a member sees upcoming activities', async ({ page, signInAs }) => {
  await signInAs('member');
  await page.goto('/discover');
  await expect(page.getByRole('heading', { level: 1, name: 'Discover' })).toBeVisible();
  await expect(page.getByRole('listitem')).not.toHaveCount(0);
  await expectAccessible(page);
});

test('a suspended member sees no activities', async ({ page, signInAs }) => {
  await signInAs('suspended');
  await page.goto('/discover');
  await expect(page.getByText("It's quiet right now.")).toBeVisible();
  await expect(page.getByRole('listitem')).toHaveCount(0);
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

test("Welcome doesn't send members to another site", async ({ page, signInAs }) => {
  await signInAs('member');
  // Parsing turns /.//evil.example into //evil.example (AUTH-04).
  await page.goto('/welcome?next=%2F.%2F%2Fevil.example');
  await expect(page).toHaveURL('/discover');
});
