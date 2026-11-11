// I'm in for all upcoming, and Leave series (REC-04). The pgTAP tests cover full dates, the dates
// a series makes later, the counts and who's notified.
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

/** The ids of the activities `member` is going to, among `dates`. */
async function goingTo(admin: SupabaseClient, member: string, dates: string[]) {
  const { data } = await admin
    .from('rsvps')
    .select('activity_id')
    .eq('user_id', member)
    .eq('status', 'going')
    .in('activity_id', dates);
  return data!.map(({ activity_id }) => activity_id as string).sort();
}

test('a member joins a whole series, then leaves it', async ({ page, poster, host }) => {
  const dates = await postSeries(host.admin, host.id);
  await page.goto(`/activities/${dates[1]}`);
  await expect(page.getByRole('button', { name: 'Leave series' })).toHaveCount(0);
  await expectAccessible(page);

  await page.getByRole('button', { name: "I'm in for all upcoming" }).click();

  await expect(page).toHaveURL(`/activities/${dates[1]}`);
  await expect(page.getByRole('status')).toHaveText("You're in for all upcoming dates.");
  await expect(page.getByRole('button', { name: '✓ Going' })).toBeVisible();
  await expect(page.getByRole('button', { name: "I'm in for all upcoming" })).toHaveCount(0);
  expect(await goingTo(poster.admin, poster.id, dates)).toEqual([...dates].sort());
  await expectAccessible(page);

  // The other date knows too.
  await page.goto(`/activities/${dates[0]}`);
  await expect(page.getByRole('button', { name: '✓ Going' })).toBeVisible();
  await page.getByRole('button', { name: 'Leave series' }).click();

  await expect(page).toHaveURL(`/activities/${dates[0]}`);
  await expect(page.getByRole('status')).toHaveText('You left the series.');
  await expect(page.getByRole('button', { name: "I'm in", exact: true })).toBeVisible();
  await expect(page.getByRole('button', { name: "I'm in for all upcoming" })).toBeVisible();
  expect(await goingTo(poster.admin, poster.id, dates)).toEqual([]);
});

test("the organizer, and an activity on its own, don't have it", async ({ page, poster }) => {
  const [mine] = await postSeries(poster.admin, poster.id);
  await page.goto(`/activities/${mine}`);
  await expect(page.getByRole('link', { name: 'Edit', exact: true })).toBeVisible();
  await expect(page.getByRole('button', { name: "I'm in for all upcoming" })).toHaveCount(0);
});

test.describe('without JavaScript', () => {
  test.use({ javaScriptEnabled: false });

  test('a member joins a whole series', async ({ page, poster, host }) => {
    const dates = await postSeries(host.admin, host.id);
    await page.goto(`/activities/${dates[0]}`);
    await page.getByRole('button', { name: "I'm in for all upcoming" }).click();

    await expect(page.getByRole('status')).toHaveText("You're in for all upcoming dates.");
    await expect(page.getByRole('button', { name: 'Leave series' })).toBeVisible();
    expect(await goingTo(poster.admin, poster.id, dates)).toEqual([...dates].sort());
  });
});
