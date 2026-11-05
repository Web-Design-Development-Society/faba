// Editing my profile (PROF-02).
import { createClient } from '@supabase/supabase-js';
import type { Database } from '../../src/lib/db.types';
import {
  expect,
  expectAccessible,
  readSession,
  SUPABASE_PUBLISHABLE_KEY,
  SUPABASE_URL,
  test,
} from './fixtures';

test('a member edits their profile, and Me shows it', async ({ page, poster }) => {
  await page.goto('/me');
  await page.getByRole('link', { name: 'Edit profile' }).click();
  await expect(page).toHaveURL('/me/edit');
  await expect(page.getByLabel('Display name')).toHaveValue('Pat Poster');
  // Other members' departments are suggestions.
  await expect(page.locator('#departments option[value="Mathematics"]')).toHaveCount(1);

  await page.getByLabel('Display name').fill('Pat P.');
  await page.getByLabel('Use initials instead').check();
  await page.getByLabel('Department (optional)').fill('Mathematics');
  await page.getByLabel('Short bio (optional)').fill('Hikes on Saturdays.');
  const interests = page.getByRole('group', { name: 'Interests (optional)' });
  await interests.getByLabel('Outdoors').check();
  await interests.getByLabel('Games').check();
  const facultyType = page.getByRole('group', { name: 'Faculty type (optional)' });
  await expect(facultyType).toHaveAccessibleDescription(
    'Only used for anonymous totals. Never shown to others.'
  );
  await facultyType.getByLabel('Part-time').check();
  await expectAccessible(page);
  await page.getByRole('button', { name: 'Save' }).click();

  await expect(page).toHaveURL('/me');
  await expect(page.getByRole('status')).toHaveText('Saved.');
  await expect(page.getByText("You're signed in as Pat P.")).toBeVisible();
  await expect(page.getByText('Mathematics', { exact: true })).toBeVisible();
  await expect(page.getByText('Hikes on Saturdays.')).toBeVisible();
  await expect(page.getByText('Interests: Outdoors, Games')).toBeVisible();

  // The form shows what was saved.
  await page.getByRole('link', { name: 'Edit profile' }).click();
  await expect(page.getByLabel('Use initials instead')).toBeChecked();
  await expect(interests.getByLabel('Outdoors')).toBeChecked();
  await expect(interests.getByLabel('Sports & Fitness')).not.toBeChecked();
  await expect(facultyType.getByLabel('Part-time')).toBeChecked();
  const { data } = await poster.admin
    .from('profile_private')
    .select('faculty_type')
    .eq('user_id', poster.id)
    .single();
  expect(data?.faculty_type).toBe('part_time');
});

test('each field says what is wrong, and keeps what was typed', async ({ page, poster }) => {
  await page.goto('/me/edit');
  // The server's checks, past the browser's.
  await page.locator('form').evaluate((form: HTMLFormElement) => {
    form.noValidate = true;
    form.querySelector('#bio')!.removeAttribute('maxlength');
  });
  await page.getByLabel('Display name').fill('P');
  await page.getByLabel('Department (optional)').fill('Biology');
  await page.getByLabel('Short bio (optional)').fill('x'.repeat(281));
  await page.getByRole('button', { name: 'Save' }).click();

  await expect(page.getByLabel('Display name')).toHaveAccessibleDescription(
    'Use at least 2 characters.'
  );
  await expect(page.getByLabel('Short bio (optional)')).toHaveAccessibleDescription(
    'Use 280 characters or fewer.'
  );
  await expect(page.getByLabel('Display name')).toHaveValue('P');
  await expect(page.getByLabel('Department (optional)')).toHaveValue('Biology');
  await expectAccessible(page);

  const { data } = await poster.admin
    .from('profiles')
    .select('display_name, department')
    .eq('id', poster.id)
    .single();
  expect(data).toEqual({ display_name: 'Pat Poster', department: null });
});

test("members can't change their own role, status or email", async ({
  context,
  baseURL,
  poster,
}) => {
  const { access_token } = await readSession(context, baseURL!);
  const member = createClient<Database>(SUPABASE_URL, SUPABASE_PUBLISHABLE_KEY, {
    global: { headers: { Authorization: `Bearer ${access_token}` } },
    auth: { persistSession: false },
  });
  const { error: role } = await member
    .from('profiles')
    .update({ role: 'admin' })
    .eq('id', poster.id);
  expect(role?.code).toBe('42501');
  const { error: status } = await member
    .from('profiles')
    .update({ status: 'active' })
    .eq('id', poster.id);
  expect(status?.code).toBe('42501');
  const { error: email } = await member
    .from('profile_private')
    .update({ email: 'pat@example.com' })
    .eq('user_id', poster.id);
  expect(email?.code).toBe('42501');

  // Their own columns, directly, are fine.
  const { error: bio } = await member
    .from('profiles')
    .update({ bio: 'Straight from the API' })
    .eq('id', poster.id);
  expect(bio).toBeNull();
  const { data } = await poster.admin.from('profiles').select('role').eq('id', poster.id).single();
  expect(data?.role).toBe('member');
});
