// Recurring activities (REC-01). The pgTAP tests cover each pattern's dates, the clock changes,
// the daily top-up, the limits and who reads a series.
import { nthWeekday, ordinalDay } from '../../src/lib/series';
import { addDays, formatDate, rexburgDate, rexburgTime } from '../../src/lib/time';
import { expect, expectAccessible, test } from './fixtures';

/** A word that search can find, such as `qzkmwa`. */
const word = () =>
  Array.from({ length: 6 }, () => String.fromCharCode(97 + Math.floor(Math.random() * 26))).join(
    ''
  );

test('an organizer posts a weekly series and lands on its first date', async ({ page, poster }) => {
  const title = `Pickleball ${word()}`;
  await page.goto('/activities/new');
  await page.getByLabel('What are you doing?').fill(title);
  await page.getByLabel('Start time').fill('19:00');
  await page.getByLabel('Where?').fill('Hart courts');
  await page.getByRole('radio', { name: 'Sports & Fitness' }).check();
  const first = await page.getByLabel('Date', { exact: true }).inputValue();
  const last = addDays(first, 21);
  await page.getByText('More options').click();
  await page.getByLabel('How often').selectOption('weekly');
  await page.getByLabel('Last date').fill(last);
  await expectAccessible(page);
  await page.getByRole('button', { name: 'Post activity' }).click();

  await expect(page.getByRole('status')).toHaveText('Posted!');
  await expect(page.getByRole('heading', { level: 1, name: title })).toBeVisible();
  await expect(page.getByText(`Repeats weekly through ${formatDate(last)}`)).toBeVisible();
  await expectAccessible(page);

  // Four dates, a week apart, each at 7 PM in Rexburg, in one series.
  const { data: dates } = await poster.admin
    .from('activities')
    .select('id, starts_at, series_id')
    .eq('organizer_id', poster.id)
    .order('starts_at');
  expect(dates!.map(({ starts_at }) => rexburgDate(new Date(starts_at)))).toEqual(
    [0, 7, 14, 21].map((days) => addDays(first, days))
  );
  expect(dates!.map(({ starts_at }) => rexburgTime(new Date(starts_at)))).toEqual([
    '19:00',
    '19:00',
    '19:00',
    '19:00',
  ]);
  expect(new Set(dates!.map(({ series_id }) => series_id)).size).toBe(1);
  expect(page.url().endsWith(`/activities/${dates![0].id}`)).toBe(true);

  // Each date is its own card, labeled Weekly.
  await page.goto(`/search?q=${encodeURIComponent(title)}`);
  const cards = page.getByRole('article').filter({ hasText: title });
  await expect(cards).toHaveCount(4);
  await expect(cards.first()).toContainText('Weekly');
  await expectAccessible(page);
});

test('the monthly choices name the chosen date', async ({ page, signInAs }) => {
  await signInAs('member');
  await page.goto('/activities/new');
  await page.getByText('More options').click();
  await page.getByRole('button', { name: 'This Saturday' }).click();
  const saturday = await page.getByLabel('Date', { exact: true }).inputValue();
  await expect(
    page.getByRole('option', { name: `Monthly on the ${ordinalDay(saturday)}` })
  ).toBeAttached();
  await expect(
    page.getByRole('option', { name: `Monthly on the ${nthWeekday(saturday)}` })
  ).toBeAttached();
  await expect(page.getByLabel('Last date')).toHaveAttribute('min', saturday);
});

test.describe('without JavaScript', () => {
  test.use({ javaScriptEnabled: false });

  test('a last date before the first is stopped before posting, with a message', async ({
    page,
    signInAs,
  }) => {
    await signInAs('member');
    await page.goto('/activities/new');
    await page.getByLabel('What are you doing?').fill('Sunrise hike up the R');
    await page.getByLabel('Start time').fill('07:00');
    await page.getByLabel('Where?').fill('R Mountain trailhead');
    await page.getByRole('radio', { name: 'Outdoors' }).check();
    const first = await page.getByLabel('Date', { exact: true }).inputValue();
    await page.getByText('More options').click();
    await page.getByLabel('How often').selectOption('monthly_nth');
    await page.getByLabel('Last date').fill(addDays(first, -1));
    await page.getByRole('button', { name: 'Post activity' }).click();

    // The browser stops a last date before the first (its min), as it does a start time at midnight,
    // so the post doesn't go out and the message is the browser's own.
    await expect(page).toHaveURL('/activities/new');
    const message = await page
      .getByLabel('Last date')
      .evaluate((input: HTMLInputElement) => input.validationMessage);
    expect(message).not.toBe('');
    await expect(page.getByLabel('How often')).toHaveValue('monthly_nth');
  });
});
