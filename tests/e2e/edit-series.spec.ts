// Editing one date or the series (REC-02). The pgTAP tests cover which dates change, the series
// itself, who's notified, and the errors.
import type { BrowserContext } from '@playwright/test';
import { createClient } from '@supabase/supabase-js';
import type { Database } from '../../src/lib/db.types';
import { weekdayName } from '../../src/lib/series';
import { addDays, rexburgDate, rexburgTime } from '../../src/lib/time';
import {
  expect,
  expectAccessible,
  readSession,
  SUPABASE_PUBLISHABLE_KEY,
  SUPABASE_URL,
  test,
} from './fixtures';

/** Posts weekly pickleball as the member signed in, from tomorrow. Returns its dates, in order. */
async function postSeries(context: BrowserContext, baseURL: string, organizer: string) {
  const { access_token } = await readSession(context, baseURL);
  const member = createClient<Database>(SUPABASE_URL, SUPABASE_PUBLISHABLE_KEY, {
    auth: { persistSession: false },
    global: { headers: { Authorization: `Bearer ${access_token}` } },
  });
  const { error } = await member.rpc('create_series', {
    title: 'Tuesday pickleball',
    category_id: 'sports',
    starts_at: new Date(Date.now() + 24 * 60 * 60 * 1000).toISOString(),
    location_name: 'Hart courts',
    freq: 'weekly',
  });
  if (error) throw new Error(`Posting failed: ${error.message}`);
  const { data } = await member
    .from('activities')
    .select('id, starts_at, title, location_name, series_detached')
    .eq('organizer_id', organizer)
    .order('starts_at');
  return { member, dates: data! };
}

test('just this date changes one date and detaches it', async ({
  page,
  context,
  baseURL,
  poster,
}) => {
  const { member, dates } = await postSeries(context, baseURL!, poster.id);
  await page.goto(`/activities/${dates[1].id}/edit`);
  await expect(page.getByRole('radio', { name: 'Just this date' })).toBeChecked();
  await expectAccessible(page);

  await page.getByLabel('Where?').fill('Madison Library');
  await page.getByRole('button', { name: 'Save' }).click();

  await expect(page).toHaveURL(`/activities/${dates[1].id}`);
  await expect(page.getByRole('status')).toHaveText('Saved.');
  await expect(page.getByText(/^Madison Library/)).toBeVisible();

  const { data: after } = await member
    .from('activities')
    .select('location_name, series_detached')
    .eq('organizer_id', poster.id)
    .order('starts_at');
  expect(after!.map(({ location_name }) => location_name)).toEqual(
    dates.map((_, n) => (n === 1 ? 'Madison Library' : 'Hart courts'))
  );
  expect(after!.map(({ series_detached }) => series_detached)).toEqual(
    dates.map((_, n) => n === 1)
  );

  // It changes on its own from now on, so the form stops asking.
  await page.goto(`/activities/${dates[1].id}/edit`);
  await expect(page.getByText('This date was changed on its own')).toBeVisible();
  await expect(page.getByRole('radio', { name: 'This and future dates' })).toHaveCount(0);
  await expectAccessible(page);
});

test('this and future dates warns about a new weekday and moves the later dates', async ({
  page,
  context,
  baseURL,
  poster,
}) => {
  const { member, dates } = await postSeries(context, baseURL!, poster.id);
  const was = rexburgDate(new Date(dates[1].starts_at));
  const now = addDays(was, 2);
  await page.goto(`/activities/${dates[1].id}/edit`);

  // The warning waits for both the choice and a new weekday.
  const warning = page.locator('[data-weekday-warning]');
  await page.getByLabel('Date').fill(now);
  await expect(warning).toBeEmpty();
  await page.getByRole('radio', { name: 'This and future dates' }).check();
  await expect(warning).toHaveText(
    `Future dates move from ${weekdayName(was)}s to ${weekdayName(now)}s. People going stay going, and they're told.`
  );
  await expectAccessible(page);

  await page.getByLabel('What are you doing?').fill('Thursday pickleball');
  await page.getByLabel('Start time').fill('19:30');
  await page.getByRole('button', { name: 'Save' }).click();

  await expect(page).toHaveURL(`/activities/${dates[1].id}`);
  await expect(page.getByRole('status')).toHaveText('Saved for this and future dates.');
  await expect(page.getByRole('heading', { level: 1, name: 'Thursday pickleball' })).toBeVisible();

  // The first date stays, and each later one moves 2 days, to 7:30 PM in Rexburg.
  const { data: after } = await member
    .from('activities')
    .select('id, title, starts_at')
    .in(
      'id',
      dates.map(({ id }) => id)
    )
    .order('starts_at');
  expect(after![0]).toEqual({
    id: dates[0].id,
    title: 'Tuesday pickleball',
    starts_at: dates[0].starts_at,
  });
  expect(after!.slice(1).map(({ title }) => title)).toEqual(
    dates.slice(1).map(() => 'Thursday pickleball')
  );
  expect(after!.slice(1).map(({ starts_at }) => rexburgDate(new Date(starts_at)))).toEqual(
    dates.slice(1).map(({ starts_at }) => addDays(rexburgDate(new Date(starts_at)), 2))
  );
  expect(
    after!.slice(1).every(({ starts_at }) => rexburgTime(new Date(starts_at)) === '19:30')
  ).toBe(true);
});

test.describe('without JavaScript', () => {
  test.use({ javaScriptEnabled: false });

  test('a save from an older page comes back with the choice made', async ({
    page,
    context,
    baseURL,
    poster,
  }) => {
    const { dates } = await postSeries(context, baseURL!, poster.id);
    await page.goto(`/activities/${dates[1].id}/edit`);
    await poster.admin.from('activities').update({ version: 5 }).eq('id', dates[1].id);

    await page.getByLabel('Where?').fill('Madison Library');
    await page.getByRole('radio', { name: 'This and future dates' }).check();
    await page.getByRole('button', { name: 'Save' }).click();

    await expect(page.getByRole('alert')).toHaveText(
      'This activity changed after you opened it. Open Edit again to see the changes.'
    );
    await expect(page.getByRole('radio', { name: 'This and future dates' })).toBeChecked();
    await expect(page.getByLabel('Where?')).toHaveValue('Madison Library');
  });
});
