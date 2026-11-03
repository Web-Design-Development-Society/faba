// Posting an activity (ACT-03).
import type { Page } from '@playwright/test';
import { rexburgDate } from '../../src/lib/time';
import { expect, expectAccessible, test } from './fixtures';

/** Fills in the required fields, starting at `startTime` on the suggested day. */
async function fillRequired(page: Page, startTime = '07:00') {
  await page.getByLabel('What are you doing?').fill('Sunrise hike up the R');
  await page.getByLabel('Start time').fill(startTime);
  await page.getByLabel('Where?').fill('R Mountain trailhead');
  await page.getByRole('radio', { name: 'Outdoors' }).check();
}

test('a member posts an activity and lands on it, going', async ({ page, poster }) => {
  await page.goto('/discover');
  await page.getByRole('link', { name: 'New activity' }).click();
  await expect(page).toHaveURL('/activities/new');
  await expect(page.getByLabel('Date')).not.toHaveValue('');
  await expectAccessible(page);

  await fillRequired(page);
  await page.getByLabel('Details (optional)').fill('Bring water.\nWe go slowly.');
  await page.getByText('More options').click();
  await page.getByLabel('End time').fill('09:30');
  await page.getByLabel('Cost').fill('Free');
  await page.getByRole('button', { name: 'Post activity' }).click();

  await expect(page).toHaveURL(/^http:\/\/[^/]+\/activities\/[0-9a-f-]{36}$/);
  await expect(page.getByRole('status')).toHaveText('Posted!');
  await expect(
    page.getByRole('heading', { level: 1, name: 'Sunrise hike up the R' })
  ).toBeVisible();
  // Intl puts a narrow no-break space before AM.
  await expect(page.getByText(/7:00\sAM to 9:30\sAM$/)).toBeVisible();
  await expect(page.getByText('Cost: Free')).toBeVisible();
  await expect(page.getByText("1 going, and you're one of them.")).toBeVisible();
  await expectAccessible(page);

  const { data: rsvps } = await poster.admin
    .from('rsvps')
    .select('user_id, status')
    .eq('activity_id', page.url().split('/').pop()!);
  expect(rsvps).toEqual([{ user_id: poster.id, status: 'going' }]);

  // "Posted!" shows once.
  await page.reload();
  await expect(page.getByRole('status')).toHaveCount(0);
});

test('the daily limit has a friendly message', async ({ page, poster }) => {
  const tomorrow = new Date(Date.now() + 24 * 60 * 60 * 1000).toISOString();
  const { error } = await poster.admin.from('activities').insert(
    Array.from({ length: 10 }, (_, i) => ({
      organizer_id: poster.id,
      category_id: 'games',
      title: `Game night ${i + 1}`,
      starts_at: tomorrow,
      location_name: 'Madison Library',
    }))
  );
  expect(error).toBeNull();

  await page.goto('/activities/new');
  await fillRequired(page);
  await page.getByRole('button', { name: 'Post activity' }).click();
  await expect(page.getByRole('alert')).toHaveText(
    'You can post up to 10 activities a day. Try again tomorrow.'
  );
  await expectAccessible(page);
});

test.describe('without JavaScript', () => {
  test.use({ javaScriptEnabled: false });

  test('a post that fails comes back with what was typed', async ({ page, poster }) => {
    // Midnight today has always passed.
    await page.goto('/activities/new');
    await fillRequired(page, '00:00');
    await page.getByLabel('Date').fill(rexburgDate(new Date()));
    await page.getByRole('button', { name: 'Post activity' }).click();

    await expect(page.getByText('Pick a time in the future.')).toBeVisible();
    await expect(page.getByLabel('Start time')).toHaveAttribute('aria-invalid', 'true');
    await expect(page.getByLabel('What are you doing?')).toHaveValue('Sunrise hike up the R');
    await expect(page.getByRole('radio', { name: 'Outdoors' })).toBeChecked();
    // No axe check here: it runs in the page, which needs JavaScript.

    const tomorrow = rexburgDate(new Date(Date.now() + 24 * 60 * 60 * 1000));
    await page.getByLabel('Date').fill(tomorrow);
    await page.getByLabel('Start time').fill('07:00');
    await page.getByRole('button', { name: 'Post activity' }).click();
    await expect(page.getByRole('status')).toHaveText('Posted!');

    // The failed post made nothing.
    const { count } = await poster.admin
      .from('activities')
      .select('*', { count: 'exact', head: true })
      .eq('organizer_id', poster.id);
    expect(count).toBe(1);
  });
});
