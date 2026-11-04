// Editing an activity (ACT-04).
import { createClient, type SupabaseClient } from '@supabase/supabase-js';
import type { Database } from '../../src/lib/db.types';
import { rexburgDate, rexburgInstant } from '../../src/lib/time';
import {
  expect,
  expectAccessible,
  readSession,
  SUPABASE_PUBLISHABLE_KEY,
  SUPABASE_URL,
  test,
} from './fixtures';

const tomorrow = rexburgDate(new Date(Date.now() + 24 * 60 * 60 * 1000));

/** Posts a hike for `organizer`, tomorrow at 7:00 unless `starts_at` says otherwise. */
async function post(admin: SupabaseClient, organizer: string, starts_at?: string) {
  const { data, error } = await admin
    .from('activities')
    .insert({
      organizer_id: organizer,
      category_id: 'outdoors',
      title: 'Sunrise hike up the R',
      starts_at: starts_at ?? rexburgInstant(tomorrow, '07:00').toISOString(),
      location_name: 'R Mountain trailhead',
    })
    .select('id')
    .single();
  if (error) throw new Error(`Posting failed: ${error.message}`);
  return data.id as string;
}

test('the organizer edits their activity, and its page says the time or place changed', async ({
  page,
  poster,
}) => {
  const id = await post(poster.admin, poster.id);
  await page.goto(`/activities/${id}`);
  await expect(page.getByText(/^Updated/)).toBeHidden();
  // The create form's draft stays out of the edit form.
  await page.evaluate(() =>
    localStorage.setItem('faba-new-activity', JSON.stringify({ title: 'A draft' }))
  );

  await page.getByRole('link', { name: 'Edit', exact: true }).click();
  await expect(page).toHaveURL(`/activities/${id}/edit`);
  await expect(page.getByLabel('What are you doing?')).toHaveValue('Sunrise hike up the R');
  await expect(page.getByLabel('Date')).toHaveValue(tomorrow);
  await expect(page.getByLabel('Start time')).toHaveValue('07:00');
  await expect(page.getByLabel('Where?')).toHaveValue('R Mountain trailhead');
  await expect(page.getByRole('radio', { name: 'Outdoors' })).toBeChecked();
  await expectAccessible(page);

  await page.getByLabel('Where?').fill('Madison Library');
  await page.getByLabel('Start time').fill('08:00');
  await page.getByRole('button', { name: 'Save' }).click();

  await expect(page).toHaveURL(`/activities/${id}`);
  await expect(page.getByRole('status')).toHaveText('Saved.');
  await expect(page.getByText(/^Madison Library/)).toBeVisible();
  // Intl puts a narrow no-break space before AM.
  await expect(page.getByText(/8:00\sAM$/)).toBeVisible();
  await expect(page.getByText('Updated just now')).toBeVisible();
  await expectAccessible(page);
});

test('a change to the description alone leaves out "Updated"', async ({ page, poster }) => {
  const id = await post(poster.admin, poster.id);
  await page.goto(`/activities/${id}/edit`);
  await page.getByLabel('Details (optional)').fill('Bring water.');
  await page.getByRole('button', { name: 'Save' }).click();

  await expect(page.getByRole('status')).toHaveText('Saved.');
  await expect(page.getByText('Bring water.')).toBeVisible();
  await expect(page.getByText(/^Updated/)).toBeHidden();
});

test('once it has started, only the description can change', async ({ page, poster }) => {
  const id = await post(
    poster.admin,
    poster.id,
    new Date(Date.now() - 60 * 60 * 1000).toISOString()
  );
  await page.goto(`/activities/${id}/edit`);
  await expect(
    page.getByText('This activity has started, so only its description can change.')
  ).toBeVisible();
  await expect(page.getByLabel('What are you doing?')).toHaveCount(0);
  await expectAccessible(page);

  await page.getByLabel('Details (optional)').fill('Thanks for coming!');
  await page.getByRole('button', { name: 'Save' }).click();
  await expect(page.getByRole('status')).toHaveText('Saved.');
  await expect(page.getByText('Thanks for coming!')).toBeVisible();
});

test('a save from an older page is told to open Edit again', async ({ page, poster }) => {
  const id = await post(poster.admin, poster.id);
  await page.goto(`/activities/${id}/edit`);
  // Saved from another tab meanwhile.
  await poster.admin.from('activities').update({ version: 2 }).eq('id', id);

  await page.getByLabel('What are you doing?').fill('Sunset hike');
  await page.getByRole('button', { name: 'Save' }).click();
  await expect(page.getByRole('alert')).toHaveText(
    'This activity changed after you opened it. Open Edit again to see the changes.'
  );
  await expect(page.getByLabel('What are you doing?')).toHaveValue('Sunset hike');
  const { data } = await poster.admin.from('activities').select('title').eq('id', id).single();
  expect(data?.title).toBe('Sunrise hike up the R');
});

test('only the organizer can edit, on the page, through the Action or the Data API', async ({
  page,
  context,
  baseURL,
  signInAs,
  host,
}) => {
  await signInAs('member');
  const id = await host.post();
  await page.goto(`/activities/${id}`);
  await expect(page.getByRole('link', { name: 'Edit', exact: true })).toHaveCount(0);

  const response = await page.goto(`/activities/${id}/edit`);
  expect(response?.status()).toBe(403);
  await expect(page.getByText('Only the organizer can edit this activity.')).toBeVisible();
  await expect(page.getByRole('button', { name: 'Save' })).toHaveCount(0);

  const action = await page.request.post('/_actions/activities.update', {
    headers: { origin: new URL(baseURL!).origin },
    form: {
      id,
      version: '1',
      title: 'Mine now',
      date: tomorrow,
      start_time: '07:00',
      location_name: 'Here',
      category_id: 'games',
    },
  });
  expect(action.status()).toBe(403);
  expect(await action.json()).toMatchObject({
    message: 'Only the organizer can edit this activity.',
  });

  // With the member's own token.
  const { access_token } = await readSession(context, baseURL!);
  const member = createClient<Database>(SUPABASE_URL, SUPABASE_PUBLISHABLE_KEY, {
    global: { headers: { Authorization: `Bearer ${access_token}` } },
    auth: { persistSession: false },
  });
  const { error: rpc } = await member.rpc('update_activity', {
    activity_id: id,
    patch: { title: 'Mine now' },
    expected_version: 1,
  });
  expect(rpc?.message).toBe('NOT_ORGANIZER');
  const { error: write } = await member
    .from('activities')
    .update({ title: 'Mine now' })
    .eq('id', id);
  expect(write?.code).toBe('42501');

  const { data } = await host.admin.from('activities').select('title').eq('id', id).single();
  expect(data?.title).toBe('Sunrise hike up the R');
});

test.describe('without JavaScript', () => {
  test.use({ javaScriptEnabled: false });

  test('a save that fails comes back with what was typed', async ({ page, poster }) => {
    const id = await post(poster.admin, poster.id);
    await page.goto(`/activities/${id}/edit`);
    // Midnight today has always passed.
    await page.getByLabel('What are you doing?').fill('Sunset hike');
    await page.getByLabel('Date').fill(rexburgDate(new Date()));
    await page.getByLabel('Start time').fill('00:00');
    await page.getByRole('button', { name: 'Save' }).click();

    await expect(page.getByText('Pick a time in the future.')).toBeVisible();
    await expect(page.getByLabel('Start time')).toHaveAttribute('aria-invalid', 'true');
    await expect(page.getByLabel('What are you doing?')).toHaveValue('Sunset hike');

    await page.getByLabel('Date').fill(tomorrow);
    await page.getByLabel('Start time').fill('07:00');
    await page.getByRole('button', { name: 'Save' }).click();
    await expect(page.getByRole('status')).toHaveText('Saved.');
    await expect(page.getByRole('heading', { level: 1, name: 'Sunset hike' })).toBeVisible();
  });
});
