// Reporting an activity or a member (MOD-01). Pat Poster reports, so the personas' daily limits
// stay as they are, and Pat's reports are deleted with Pat.
import { expect, expectAccessible, test } from './fixtures';

// Sam Suspended, a persona.
const SAM = '00000000-0000-4000-8000-000000000005';

test('a member reports an activity from its ⋯ menu, once', async ({ page, poster, host }) => {
  const id = await host.post();
  await page.goto(`/activities/${id}`);
  await page.getByLabel('More actions').click();
  await page.getByRole('link', { name: 'Report' }).click();
  await expect(page).toHaveURL(`/activities/${id}/report`);
  await expect(page.getByRole('heading', { level: 1 })).toHaveText('Report this activity');
  await expect(page.getByText('Only moderators see who sent a report.')).toBeVisible();
  await expectAccessible(page);

  await page.getByLabel('Spam / commercial').check();
  await page.getByLabel('Note (optional)').fill('Selling tickets');
  await page.getByRole('button', { name: 'Send report' }).click();
  await expect(page).toHaveURL(`/activities/${id}`);
  await expect(page.getByRole('status')).toHaveText('Thanks, a moderator will review this.');
  // A report hides nothing by itself.
  await expect(page.getByRole('heading', { level: 1 })).toHaveText('Sunrise hike up the R');
  const { data } = await host.admin
    .from('reports')
    .select('reporter_id, target_type, reason, note, status')
    .eq('target_id', id);
  expect(data).toEqual([
    {
      reporter_id: poster.id,
      target_type: 'activity',
      reason: 'spam',
      note: 'Selling tickets',
      status: 'open',
    },
  ]);

  await page.goto(`/activities/${id}/report`);
  await expect(
    page.getByText("You've already reported this. A moderator will review it.")
  ).toBeVisible();
  await expect(page.getByRole('button', { name: 'Send report' })).toHaveCount(0);
});

test('a member reports a member from their profile', async ({ page, poster, host }) => {
  await page.goto(`/people/${host.id}`);
  await page.getByLabel('More actions').click();
  await page.getByRole('link', { name: 'Report' }).click();
  await expect(page.getByRole('heading', { level: 1 })).toHaveText('Report this member');
  await page.getByLabel('Unsafe').check();
  await page.getByRole('button', { name: 'Send report' }).click();
  await expect(page).toHaveURL(`/people/${host.id}`);
  await expect(page.getByRole('status')).toHaveText('Thanks, a moderator will review this.');
  const { data } = await host.admin
    .from('reports')
    .select('reporter_id, target_type, reason, note')
    .eq('target_id', host.id);
  expect(data).toEqual([
    { reporter_id: poster.id, target_type: 'profile', reason: 'unsafe', note: null },
  ]);
});

test("10 reports a day, and nothing of their own or that they can't see", async ({
  page,
  poster,
  host,
}) => {
  await poster.admin.from('reports').insert(
    Array.from({ length: 10 }, () => ({
      reporter_id: poster.id,
      target_type: 'profile',
      target_id: crypto.randomUUID(),
      reason: 'other',
    }))
  );
  await page.goto(`/people/${host.id}/report`);
  await page.getByLabel('Other').check();
  await page.getByLabel('Note (optional)').fill('Rude at the hike');
  await page.getByRole('button', { name: 'Send report' }).click();
  await expect(page.getByRole('alert')).toHaveText(
    'You can send up to 10 reports a day. Try again tomorrow.'
  );
  // What was typed stays.
  await expect(page.getByLabel('Other')).toBeChecked();
  await expect(page.getByLabel('Note (optional)')).toHaveValue('Rude at the hike');

  await page.goto(`/people/${poster.id}/report`);
  await expect(page.getByText("You can't report your own profile.")).toBeVisible();
  await expect(page.getByRole('button', { name: 'Send report' })).toHaveCount(0);

  const response = await page.goto(`/people/${SAM}/report`);
  expect(response?.status()).toBe(404);
  await expect(page.getByText('This member is no longer active.')).toBeVisible();
});
