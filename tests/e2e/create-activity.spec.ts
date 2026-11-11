// Posting an activity (ACT-03).
import type { Page } from '@playwright/test';
import { quickDates, rexburgDate } from '../../src/lib/time';
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
  await page.getByRole('link', { name: 'Post', exact: true }).click();
  await expect(page).toHaveURL('/activities/new');
  await expect(page.getByLabel('Date', { exact: true })).not.toHaveValue('');
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
  // Intl puts thin spaces around the dash and a narrow no-break space before AM.
  await expect(page.getByText(/7:00\s–\s9:30\sAM$/)).toBeVisible();
  await expect(page.getByText('Cost: Free')).toBeVisible();
  await expect(page.getByText('1 going')).toBeVisible();
  await expect(page.getByText("You're hosting")).toBeVisible();
  await expectAccessible(page);

  const { data: rsvps } = await poster.admin
    .from('rsvps')
    .select('user_id, status')
    .eq('activity_id', page.url().split('/').pop()!);
  expect(rsvps).toEqual([{ user_id: poster.id, status: 'going' }]);

  // "Posted!" shows once.
  await page.reload();
  await expect(page.getByRole('status')).toBeEmpty();
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

test('quick picks set the date, and the time rules are checked before posting', async ({
  page,
  signInAs,
}) => {
  await signInAs('member');
  await page.goto('/activities/new');
  const { today, tomorrow, saturday } = quickDates(new Date());
  await page.getByRole('button', { name: 'Tomorrow' }).click();
  await expect(page.getByLabel('Date', { exact: true })).toHaveValue(tomorrow);
  await page.getByRole('button', { name: 'This Saturday' }).click();
  await expect(page.getByLabel('Date', { exact: true })).toHaveValue(saturday);
  await page.getByRole('button', { name: 'Today' }).click();
  await expect(page.getByLabel('Date', { exact: true })).toHaveValue(today);

  // Midnight today has always passed, so the browser stops the post.
  await fillRequired(page, '00:00');
  await page.getByRole('button', { name: 'Post activity' }).click();
  await expect(page).toHaveURL('/activities/new');
  await expect(page.getByLabel('Start time')).toHaveJSProperty(
    'validationMessage',
    'Pick a time in the future.'
  );

  await page.getByRole('button', { name: 'Tomorrow' }).click();
  await page.getByLabel('Start time').fill('07:00');
  await page.getByText('More options').click();
  await page.getByLabel('End time').fill('06:00');
  await page.getByRole('button', { name: 'Post activity' }).click();
  await expect(page).toHaveURL('/activities/new');
  await expect(page.getByLabel('End time')).toHaveJSProperty(
    'validationMessage',
    'End after the start time.'
  );
});

test('the draft survives a failed post, and goes once posted', async ({ page, poster }) => {
  await page.goto('/activities/new');
  await fillRequired(page);
  await page.reload();
  await expect(page.getByText('We kept what you typed last time.')).toBeVisible();
  await expect(page.getByLabel('What are you doing?')).toHaveValue('Sunrise hike up the R');
  await expect(page.getByRole('radio', { name: 'Outdoors' })).toBeChecked();

  await page.getByRole('button', { name: 'Start over' }).click();
  await expect(page.getByLabel('What are you doing?')).toHaveValue('');
  await expect(page.getByText('We kept what you typed last time.')).toBeHidden();

  // The connection drops while posting.
  await fillRequired(page);
  await page.route(/_action=/, (route) => route.abort());
  const failed = page.waitForEvent('requestfailed');
  await page.getByRole('button', { name: 'Post activity' }).click();
  await failed;
  await page.unroute(/_action=/);

  await page.goto('/activities/new');
  await expect(page.getByLabel('What are you doing?')).toHaveValue('Sunrise hike up the R');
  await page.getByRole('button', { name: 'Post activity' }).click();
  await expect(page.getByRole('status')).toHaveText('Posted!');
  const { count } = await poster.admin
    .from('activities')
    .select('*', { count: 'exact', head: true })
    .eq('organizer_id', poster.id);
  expect(count).toBe(1);

  // Posted, so the next form starts empty. "Posted!" comes with the page, and its script clears
  // the draft just after.
  await expect
    .poll(() => page.evaluate(() => localStorage.getItem('faba-new-activity')))
    .toBeNull();
  await page.goto('/activities/new');
  await expect(page.getByLabel('What are you doing?')).toHaveValue('');
  await expect(page.getByText('We kept what you typed last time.')).toBeHidden();
});

test.describe('without JavaScript', () => {
  test.use({ javaScriptEnabled: false });

  test('a post that fails comes back with what was typed', async ({ page, poster }) => {
    // Midnight today has always passed.
    await page.goto('/activities/new');
    await fillRequired(page, '00:00');
    await page.getByLabel('Date', { exact: true }).fill(rexburgDate(new Date()));
    await page.getByRole('button', { name: 'Post activity' }).click();

    await expect(page.getByText('Pick a time in the future.')).toBeVisible();
    await expect(page.getByLabel('Start time')).toHaveAttribute('aria-invalid', 'true');
    await expect(page.getByLabel('What are you doing?')).toHaveValue('Sunrise hike up the R');
    await expect(page.getByRole('radio', { name: 'Outdoors' })).toBeChecked();
    // No axe check here: it runs in the page, which needs JavaScript.

    const tomorrow = rexburgDate(new Date(Date.now() + 24 * 60 * 60 * 1000));
    await page.getByLabel('Date', { exact: true }).fill(tomorrow);
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
