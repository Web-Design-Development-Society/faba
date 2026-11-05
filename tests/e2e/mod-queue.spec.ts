// The moderators' reports queue (MOD-02). Other tests report at the same time, so each report here
// has a tag of its own.
import { expect, expectAccessible, test } from './fixtures';

// Oscar Organizer, a persona.
const OSCAR = '00000000-0000-4000-8000-000000000002';

test('a moderator sees open reports, oldest first, and dismisses one with a reason', async ({
  page,
  signInAs,
  host,
}) => {
  await signInAs('moderator');
  const tag = crypto.randomUUID().slice(0, 8);
  const title = `Ticket sale ${tag}`;
  const id = await host.post({ title });
  // Hana reported Oscar 2 days ago, and someone who has since deleted their account reported
  // Hana's activity just now.
  const { data: reports } = await host.admin
    .from('reports')
    .insert([
      {
        reporter_id: host.id,
        target_type: 'profile',
        target_id: OSCAR,
        reason: 'unsafe',
        note: `Shouted at the hike ${tag}`,
        created_at: new Date(Date.now() - 2 * 24 * 60 * 60 * 1000).toISOString(),
      },
      {
        reporter_id: null,
        target_type: 'activity',
        target_id: id,
        reason: 'spam',
        note: null,
        created_at: new Date().toISOString(),
      },
    ])
    .select('id');
  try {
    await page.goto('/me');
    await page.getByRole('link', { name: /^Open reports: \d+$/ }).click();
    await expect(page).toHaveURL('/mod');

    const older = page.getByRole('article').filter({ hasText: `Shouted at the hike ${tag}` });
    await expect(older.getByRole('link', { name: 'Oscar Organizer' })).toHaveAttribute(
      'href',
      `/people/${OSCAR}`
    );
    await expect(older).toContainText('Unsafe');
    await expect(older).toContainText('Reported by Hana Host · 2d ago');
    const newer = page.getByRole('article').filter({ hasText: title });
    await expect(newer).toContainText('Spam / commercial');
    await expect(newer).toContainText("Reported by a member who's no longer active · just now");
    const all = await page.getByRole('article').allTextContents();
    expect(all.findIndex((text) => text.includes(`Shouted at the hike ${tag}`))).toBeLessThan(
      all.findIndex((text) => text.includes(title))
    );
    await expectAccessible(page);

    await newer.getByRole('button', { name: 'Dismiss' }).click();
    const sheet = page.getByRole('dialog', { name: 'Dismiss this report?' });
    await sheet.getByLabel('Reason, for the audit log').fill('Free event, not a sale');
    await sheet.getByRole('button', { name: 'Dismiss report' }).click();
    await expect(page).toHaveURL('/mod');
    await expect(page.getByRole('status')).toHaveText('Report dismissed.');
    await expect(page.getByRole('article').filter({ hasText: title })).toHaveCount(0);
    await expect(older).toBeVisible();

    const { data } = await host.admin
      .from('reports')
      .select('status, resolution_note')
      .eq('id', reports![1].id)
      .single();
    expect(data).toEqual({ status: 'dismissed', resolution_note: 'Free event, not a sale' });
  } finally {
    // Hana's report goes with her account. This one has no reporter.
    await host.admin.from('reports').delete().eq('id', reports![1].id);
  }
});

test("members don't see open reports, or the queue", async ({ page, signInAs }) => {
  await signInAs('member');
  await page.goto('/me');
  await expect(page.getByRole('link', { name: /Open reports/ })).toHaveCount(0);

  const response = await page.goto('/mod');
  expect(response?.status()).toBe(403);
  await expect(page.getByText('Only moderators can see the reports queue.')).toBeVisible();
  await expect(page.getByRole('article')).toHaveCount(0);
});
