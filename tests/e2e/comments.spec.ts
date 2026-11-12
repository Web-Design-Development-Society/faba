// Comments on activities (ACT-12). The pgTAP tests cover the rules, and this checks the page.
// Written while E2E is paused; not yet run.
import { expect, expectAccessible, test } from './fixtures';

test('a member asks a question under an activity, then deletes it', async ({
  page,
  signInAs,
  host,
}) => {
  await signInAs('member');
  const tag = `c${crypto.randomUUID().slice(0, 8)}`;
  const id = await host.post({ title: `Trail ${tag}` });

  await page.goto(`/activities/${id}`);
  await page.getByLabel('Ask a question or leave a comment').fill('Is there parking?');
  await page.getByRole('button', { name: 'Post comment' }).click();
  await expect(page.getByRole('status')).toHaveText('Comment posted.');
  await expect(page.getByText('Is there parking?')).toBeVisible();
  await expectAccessible(page);

  await page.getByRole('button', { name: 'Delete my comment' }).click();
  await expect(page.getByRole('status')).toHaveText('Comment deleted.');
  await expect(page.getByText('Is there parking?')).toHaveCount(0);
});

test('a moderator hides a reported comment, and says why', async ({ page, signInAs, host }) => {
  await signInAs('member');
  const tag = `c${crypto.randomUUID().slice(0, 8)}`;
  const id = await host.post({ title: `Trail ${tag}` });
  await page.goto(`/activities/${id}`);
  await page.getByLabel('Ask a question or leave a comment').fill(`Buy things here ${tag}`);
  await page.getByRole('button', { name: 'Post comment' }).click();
  await expect(page.getByRole('status')).toHaveText('Comment posted.');

  await signInAs('moderator');
  await page.goto(`/activities/${id}`);
  await page.getByRole('button', { name: 'Hide comment' }).first().click();
  const sheet = page.getByRole('dialog');
  await sheet.getByLabel('Reason, for the audit log').fill('Spam');
  await sheet.getByRole('button', { name: 'Hide comment' }).click();
  await expect(page.getByRole('status')).toHaveText('Comment hidden.');
  await expectAccessible(page);
});
