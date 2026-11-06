// Showing my email on my profile, or not (PROF-04).
import { expect, expectAccessible, test } from './fixtures';

test('a member chooses to show their email on their profile, and to hide it again', async ({
  page,
  poster,
}) => {
  const { data } = await poster.admin
    .from('profile_private')
    .select('email')
    .eq('user_id', poster.id)
    .single();
  const email = data!.email as string;

  await page.goto('/me/edit');
  const share = page.getByLabel('Show my email on my profile');
  // Off to begin with.
  await expect(share).not.toBeChecked();
  await expect(page.getByText(`${email}. Only signed-in members see it.`)).toBeVisible();
  await expectAccessible(page);
  await share.check();
  await page.getByRole('button', { name: 'Save' }).click();
  await expect(page).toHaveURL('/me');
  await expect(page.getByRole('status')).toHaveText('Saved.');

  await page.goto(`/people/${poster.id}`);
  await expect(page.getByRole('link', { name: email })).toHaveAttribute('href', `mailto:${email}`);

  await page.goto('/me/edit');
  await expect(share).toBeChecked();
  await share.uncheck();
  await page.getByRole('button', { name: 'Save' }).click();
  await expect(page).toHaveURL('/me');
  await page.goto(`/people/${poster.id}`);
  await expect(page.getByText('Email')).toHaveCount(0);
});

test("moderators see a member's email even when they don't share it", async ({
  page,
  signInAs,
  host,
}) => {
  await signInAs('moderator');
  const { data } = await host.admin
    .from('profile_private')
    .select('email')
    .eq('user_id', host.id)
    .single();
  const email = data!.email as string;

  await page.goto(`/people/${host.id}`);
  await expect(page.getByText('Email, for moderators only:')).toBeVisible();
  await expect(page.getByRole('link', { name: email })).toHaveAttribute('href', `mailto:${email}`);
});
