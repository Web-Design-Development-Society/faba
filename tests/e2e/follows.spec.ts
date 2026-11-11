// Following a category (NOTIF-09). The pgTAP tests cover the batched notice, who gets it and
// unfollowing.
import { expect, expectAccessible, test } from './fixtures';

test('a member follows a category from Discover, and the button says so', async ({
  page,
  signInAs,
}) => {
  await signInAs('member');
  await page.goto('/discover?cat=outdoors');

  const follow = page.getByRole('button', { name: /^Follow/ });
  await expect(follow).toHaveAttribute('aria-pressed', 'false');
  await expectAccessible(page);

  await follow.click();
  await expect(page.getByRole('status')).toHaveText(
    "You're following it. New activities will show up in your notifications."
  );
  await expect(page).toHaveURL('/discover?cat=outdoors');
  await expect(page.getByRole('button', { name: /^Following/ })).toHaveAttribute(
    'aria-pressed',
    'true'
  );

  await page.getByRole('button', { name: /^Following/ }).click();
  await expect(page.getByRole('status')).toHaveText("You're not following it anymore.");
  await expect(page.getByRole('button', { name: /^Follow/ })).toHaveAttribute(
    'aria-pressed',
    'false'
  );
});
