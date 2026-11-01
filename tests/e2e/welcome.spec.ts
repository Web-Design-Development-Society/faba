// Welcome, where new members accept the community guidelines (PROF-01).
import { expect, expectAccessible, test } from './fixtures';

test('a new member goes through Welcome to the page they asked for', async ({
  page,
  newMember,
}) => {
  await page.goto('/discover?cat=games');
  await expect(page).toHaveURL('/welcome?next=%2Fdiscover%3Fcat%3Dgames');
  await expect(page.getByRole('heading', { level: 1, name: 'Welcome to FABA' })).toBeVisible();
  await expect(page.getByLabel('Display name')).toHaveValue(newMember.displayName);
  await expect(page.getByRole('img', { name: 'Your Google photo' })).toBeVisible();
  await expect(page.getByRole('listitem')).toHaveCount(3);
  await expect(page.getByRole('link', { name: 'Read the full guidelines' })).toHaveAttribute(
    'href',
    '/guidelines'
  );
  await expect(page.getByRole('link', { name: 'Add more to your profile later' })).toHaveAttribute(
    'href',
    '/me'
  );
  await expectAccessible(page);

  await page.getByLabel('Display name').fill('Nia N.');
  await page.getByLabel('Use initials instead').check();
  await page.getByLabel('I agree to the community guidelines').check();
  await page.getByRole('button', { name: "Let's go" }).click();
  await expect(page).toHaveURL('/discover?cat=games');
  await expect(page.getByText('Signed in as Nia N.')).toBeVisible();

  // Welcome doesn't come back.
  await page.goto('/welcome');
  await expect(page).toHaveURL('/discover');
});

test('Welcome says what to fix', async ({ page, newMember }) => {
  await page.goto('/welcome');
  // Spaces get past the browser's minimum length, but not the server's.
  await page.getByLabel('Display name').fill('   ');
  await page.getByLabel('I agree to the community guidelines').check();
  await page.getByRole('button', { name: "Let's go" }).click();
  await expect(page.getByText('Use at least 2 characters.')).toBeVisible();
  await expect(page.getByLabel('Display name')).toHaveAttribute('aria-invalid', 'true');
  await expect(page.getByLabel('Display name')).toHaveValue(newMember.displayName);
  await expectAccessible(page);
});
