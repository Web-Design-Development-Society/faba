// Cancelling one date of a series (REC-03). The pgTAP tests cover the series carrying on and who's
// notified, and cancel-activity.spec.ts covers cancelling and restoring.
import type { SupabaseClient } from '@supabase/supabase-js';
import { expect, expectAccessible, test } from './fixtures';

const DAY = 24 * 60 * 60 * 1000;

/** Posts a weekly series for `organizer` with two dates, tomorrow and a week on. Returns their ids. */
async function postSeries(admin: SupabaseClient, organizer: string) {
  const today = new Date().toISOString().slice(0, 10);
  const { data: series, error } = await admin
    .from('activity_series')
    .insert({
      organizer_id: organizer,
      category_id: 'sports',
      title: 'Tuesday pickleball',
      location_name: 'Hart courts',
      freq: 'weekly',
      start_date: today,
      start_time: '19:00',
      generated_through: today,
    })
    .select('id')
    .single();
  if (error) throw new Error(`Posting the series failed: ${error.message}`);
  const { data: dates, error: failed } = await admin
    .from('activities')
    .insert(
      [1, 8].map((days) => ({
        organizer_id: organizer,
        category_id: 'sports',
        title: 'Tuesday pickleball',
        starts_at: new Date(Date.now() + days * DAY).toISOString(),
        location_name: 'Hart courts',
        series_id: series.id,
      }))
    )
    .select('id, starts_at')
    .order('starts_at');
  if (failed) throw new Error(`Posting its dates failed: ${failed.message}`);
  return dates.map(({ id }) => id as string);
}

test('the organizer cancels one date in 2 taps, and the series continues', async ({
  page,
  poster,
}) => {
  const [first, next] = await postSeries(poster.admin, poster.id);
  await page.goto(`/activities/${first}`);

  await page.getByRole('button', { name: 'Cancel this date' }).click();
  const sheet = page.getByRole('dialog', { name: 'Cancel this date?' });
  await expect(sheet.getByText('Only this date is cancelled. The series continues.')).toBeVisible();
  await expectAccessible(page);
  await sheet.getByRole('button', { name: 'Yes, cancel it' }).click();

  await expect(page).toHaveURL(`/activities/${first}`);
  await expect(page.getByRole('status')).toHaveText('Cancelled.');
  await expect(page.getByText('Cancelled', { exact: true })).toBeVisible();
  await expect(page.getByRole('button', { name: 'Cancel this date' })).toHaveCount(0);
  await expectAccessible(page);

  // The next date is still on.
  const { data } = await poster.admin
    .from('activities')
    .select('id, status')
    .in('id', [first, next])
    .order('starts_at');
  expect(data!.map(({ status }) => status)).toEqual(['cancelled', 'published']);
  await page.goto(`/activities/${next}`);
  await expect(page.getByRole('button', { name: 'Cancel this date' })).toBeVisible();
});

test('Edit has it too, with a reason, and restores the date', async ({ page, poster }) => {
  const [first] = await postSeries(poster.admin, poster.id);
  await page.goto(`/activities/${first}/edit`);

  await page.getByRole('button', { name: 'Cancel this date' }).click();
  const sheet = page.getByRole('dialog', { name: 'Cancel this date?' });
  await sheet.getByLabel('Reason (optional)').fill('Thanksgiving');
  await sheet.getByRole('button', { name: 'Yes, cancel it' }).click();

  await expect(page).toHaveURL(`/activities/${first}`);
  await expect(page.getByText('Cancelled: Thanksgiving')).toBeVisible();

  await page.getByRole('link', { name: 'Edit', exact: true }).click();
  await page.getByRole('button', { name: 'Restore activity' }).click();
  await expect(page.getByRole('status')).toHaveText("Restored. It's back on.");
});

test("only the organizer sees it, and an activity on its own doesn't have it", async ({
  page,
  poster,
  host,
}) => {
  // Hana's series date, and Pat's own activity that isn't in a series.
  const [theirs] = await postSeries(host.admin, host.id);
  await page.goto(`/activities/${theirs}`);
  await expect(page.getByRole('heading', { level: 1, name: 'Tuesday pickleball' })).toBeVisible();
  await expect(page.getByRole('button', { name: 'Cancel this date' })).toHaveCount(0);

  const { data: mine } = await poster.admin
    .from('activities')
    .insert({
      organizer_id: poster.id,
      category_id: 'outdoors',
      title: 'Sunrise hike up the R',
      starts_at: new Date(Date.now() + DAY).toISOString(),
      location_name: 'R Mountain trailhead',
    })
    .select('id')
    .single();
  await page.goto(`/activities/${mine!.id}`);
  await expect(page.getByRole('link', { name: 'Edit', exact: true })).toBeVisible();
  await expect(page.getByRole('button', { name: 'Cancel this date' })).toHaveCount(0);
});

test.describe('without JavaScript', () => {
  test.use({ javaScriptEnabled: false });

  test('the organizer cancels one date', async ({ page, poster }) => {
    const [first] = await postSeries(poster.admin, poster.id);
    await page.goto(`/activities/${first}`);
    await page.getByRole('button', { name: 'Cancel this date' }).click();
    await page.getByRole('dialog').getByRole('button', { name: 'Yes, cancel it' }).click();

    await expect(page).toHaveURL(`/activities/${first}`);
    await expect(page.getByRole('status')).toHaveText('Cancelled.');
  });
});
