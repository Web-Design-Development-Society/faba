// Cancelling and restoring an activity (ACT-05).
import { createClient, type SupabaseClient } from '@supabase/supabase-js';
import type { Database } from '../../src/lib/db.types';
import {
  expect,
  expectAccessible,
  readSession,
  SUPABASE_PUBLISHABLE_KEY,
  SUPABASE_URL,
  test,
} from './fixtures';

const HOUR = 60 * 60 * 1000;

/** Posts a hike for `organizer`, tomorrow unless `starts_at` says otherwise. */
async function post(admin: SupabaseClient, organizer: string, starts_at?: string) {
  const { data, error } = await admin
    .from('activities')
    .insert({
      organizer_id: organizer,
      category_id: 'outdoors',
      title: 'Sunrise hike up the R',
      starts_at: starts_at ?? new Date(Date.now() + 24 * HOUR).toISOString(),
      location_name: 'R Mountain trailhead',
    })
    .select('id')
    .single();
  if (error) throw new Error(`Posting failed: ${error.message}`);
  return data.id as string;
}

test('the organizer cancels their activity with a reason, then restores it', async ({
  page,
  context,
  baseURL,
  poster,
}) => {
  const id = await post(poster.admin, poster.id);
  await page.goto(`/activities/${id}/edit`);
  await page.getByRole('button', { name: 'Cancel activity' }).click();
  const sheet = page.getByRole('dialog', { name: 'Cancel this activity?' });
  await expectAccessible(page);

  await sheet.getByRole('button', { name: 'No, keep it' }).click();
  await expect(sheet).toBeHidden();
  await page.getByRole('button', { name: 'Cancel activity' }).click();
  await sheet.getByLabel('Reason (optional)').fill('Rained out. We will try next week.');
  await sheet.getByRole('button', { name: 'Yes, cancel it' }).click();

  await expect(page).toHaveURL(`/activities/${id}`);
  await expect(page.getByRole('status')).toHaveText('Cancelled.');
  await expect(page.getByText('Cancelled: Rained out. We will try next week.')).toBeVisible();
  await expectAccessible(page);

  await page.getByRole('link', { name: 'Edit', exact: true }).click();
  await expect(page.getByRole('button', { name: 'Cancel activity' })).toHaveCount(0);
  await page.getByRole('button', { name: 'Restore activity' }).click();

  await expect(page).toHaveURL(`/activities/${id}`);
  await expect(page.getByRole('status')).toHaveText("Restored. It's back on.");
  await expect(page.getByText(/^Cancelled/)).toHaveCount(0);

  // There's no hard delete, even for the organizer.
  const { access_token } = await readSession(context, baseURL!);
  const organizer = createClient<Database>(SUPABASE_URL, SUPABASE_PUBLISHABLE_KEY, {
    global: { headers: { Authorization: `Bearer ${access_token}` } },
    auth: { persistSession: false },
  });
  const { error } = await organizer.from('activities').delete().eq('id', id);
  expect(error?.code).toBe('42501');
});

test('once it has started, it can be cancelled but not restored', async ({ page, poster }) => {
  const id = await post(poster.admin, poster.id, new Date(Date.now() - HOUR).toISOString());
  await page.goto(`/activities/${id}/edit`);
  await page.getByRole('button', { name: 'Cancel activity' }).click();
  await page.getByRole('dialog').getByRole('button', { name: 'Yes, cancel it' }).click();

  await expect(page.getByRole('status')).toHaveText('Cancelled.');
  await expect(page.getByText('Cancelled', { exact: true })).toBeVisible();
  await page.goto(`/activities/${id}/edit`);
  await expect(
    page.getByText("This activity is cancelled. It has started, so it can't be restored.")
  ).toBeVisible();
  await expect(page.getByRole('button', { name: 'Restore activity' })).toHaveCount(0);
});

test('Restore from a page opened before the start says why it failed', async ({ page, poster }) => {
  const id = await post(poster.admin, poster.id);
  await poster.admin
    .from('activities')
    .update({ status: 'cancelled', cancelled_at: new Date().toISOString() })
    .eq('id', id);
  await page.goto(`/activities/${id}/edit`);
  // It starts meanwhile.
  await poster.admin
    .from('activities')
    .update({ starts_at: new Date(Date.now() - HOUR).toISOString() })
    .eq('id', id);

  await page.getByRole('button', { name: 'Restore activity' }).click();
  await expect(page.getByRole('alert')).toHaveText(
    "This activity has started, so it can't be restored."
  );
  const { data } = await poster.admin.from('activities').select('status').eq('id', id).single();
  expect(data?.status).toBe('cancelled');
});

test('only the organizer can cancel or restore, through the Action or the Data API', async ({
  page,
  context,
  baseURL,
  signInAs,
  host,
}) => {
  await signInAs('member');
  const id = await host.post();
  for (const action of ['cancel', 'restore']) {
    const response = await page.request.post(`/_actions/activities.${action}`, {
      headers: { origin: new URL(baseURL!).origin },
      form: { id },
    });
    expect(response.status()).toBe(403);
    expect(await response.json()).toMatchObject({
      message: 'Only the organizer can edit this activity.',
    });
  }

  // With the member's own token.
  const { access_token } = await readSession(context, baseURL!);
  const member = createClient<Database>(SUPABASE_URL, SUPABASE_PUBLISHABLE_KEY, {
    global: { headers: { Authorization: `Bearer ${access_token}` } },
    auth: { persistSession: false },
  });
  const { error: rpc } = await member.rpc('cancel_activity', { activity_id: id });
  expect(rpc?.message).toBe('NOT_ORGANIZER');
  const { error: write } = await member
    .from('activities')
    .update({ status: 'cancelled', cancelled_at: new Date().toISOString() })
    .eq('id', id);
  expect(write?.code).toBe('42501');

  const { data } = await host.admin.from('activities').select('status').eq('id', id).single();
  expect(data?.status).toBe('published');
});

test.describe('without JavaScript', () => {
  test.use({ javaScriptEnabled: false });

  test('Cancel activity asks first, then cancels', async ({ page, poster }) => {
    const id = await post(poster.admin, poster.id);
    await page.goto(`/activities/${id}/edit`);
    await page.getByRole('button', { name: 'Cancel activity' }).click();
    const sheet = page.getByRole('dialog', { name: 'Cancel this activity?' });
    await sheet.getByLabel('Reason (optional)').fill('Snowed in');
    await sheet.getByRole('button', { name: 'Yes, cancel it' }).click();

    await expect(page).toHaveURL(`/activities/${id}`);
    await expect(page.getByRole('status')).toHaveText('Cancelled.');
    await expect(page.getByText('Cancelled: Snowed in')).toBeVisible();
  });
});
