// The New activity form's layout (UI-06), and When? on New and Edit (UI-13). Each project runs at
// its own width, so this checks a 320 px iPhone SE, a 412 px Pixel and a desktop.
// create-activity.spec.ts covers posting.
import { expect, expectAccessible, test } from './fixtures';

const BLUE = 'rgb(11, 91, 211)';

test('the form reads as sections, fits the screen, and keeps the bottom bar', async ({
  page,
  poster,
}) => {
  expect(poster.id).toBeTruthy();
  await page.goto('/discover');
  await page.getByRole('navigation', { name: 'Main' }).getByRole('link', { name: 'Post' }).click();
  await expect(page).toHaveURL('/activities/new');

  // The bottom bar stays, with Post as the current item.
  const post = page.getByRole('navigation', { name: 'Main' }).getByRole('link', { name: 'Post' });
  await expect(post).toHaveAttribute('aria-current', 'page');

  // Every text field is the form's width, with an example in it.
  const form = page.locator('form[data-activity-form]');
  const formWidth = (await form.boundingBox())!.width;
  for (const field of [
    page.getByLabel('What are you doing?'),
    page.getByLabel('Where?'),
    page.getByLabel('Details (optional)'),
  ]) {
    expect(Math.abs((await field.boundingBox())!.width - formWidth)).toBeLessThanOrEqual(1);
    await expect(field).toHaveAttribute('placeholder', /^(e\.g\.|Add anything)/);
  }

  // The date and start time sit side by side in one box, and stack on a narrow phone.
  const [date, time] = [
    (await page.getByLabel('Date', { exact: true }).boundingBox())!,
    (await page.getByLabel('Start time').boundingBox())!,
  ];
  if (page.viewportSize()!.width < 360) expect(time.y).toBeGreaterThan(date.y + date.height - 1);
  else expect(Math.abs(time.y - date.y)).toBeLessThanOrEqual(2);

  // A category is a chip: tapping its name chooses it, and it turns FABA blue.
  const games = page.getByRole('radio', { name: 'Games' });
  await page.locator('.pill', { hasText: 'Games' }).click();
  await expect(games).toBeChecked();
  await expect(page.locator('.pill', { hasText: 'Games' })).toHaveCSS('background-color', BLUE);

  // Cancel goes back where the member came from, beside Post activity.
  await expect(page.getByRole('link', { name: 'Cancel' })).toHaveAttribute('href', '/discover');
  await expect(page.getByRole('button', { name: 'Post activity' })).toBeVisible();

  expect(await page.evaluate(() => document.documentElement.scrollWidth <= window.innerWidth)).toBe(
    true
  );
  await expectAccessible(page);
});

test('When? is just a date and a time, on New and Edit (UI-13)', async ({ page, poster }) => {
  const { data } = await poster.admin
    .from('activities')
    .insert({
      organizer_id: poster.id,
      category_id: 'games',
      title: 'Board game night',
      starts_at: new Date(Date.now() + 24 * 60 * 60 * 1000).toISOString(),
      location_name: 'Library',
    })
    .select('id')
    .single();

  for (const path of ['/activities/new', `/activities/${data!.id}/edit`]) {
    await page.goto(path);
    // No shortcuts: the browser's own calendar and time picker are all there is.
    const when = page.getByRole('group', { name: 'When?' });
    await expect(when.getByRole('button')).toHaveCount(0);
    for (const name of ['Today', 'Tomorrow', 'This Saturday']) {
      await expect(page.getByRole('button', { name, exact: true })).toHaveCount(0);
    }
    await expect(when.getByLabel('Date', { exact: true })).toHaveAttribute('type', 'date');
    await expect(when.getByLabel('Start time')).toHaveAttribute('type', 'time');
    await expectAccessible(page);
  }
});

test('activities have no tags, on the form or the page (UI-09)', async ({ page, poster }) => {
  await page.goto('/activities/new');
  await page.getByText('More options').click();
  await expect(page.getByRole('group', { name: 'Tags' })).toHaveCount(0);

  // Even one tagged before tags were removed shows none.
  const { data } = await poster.admin
    .from('activities')
    .insert({
      organizer_id: poster.id,
      category_id: 'family',
      title: 'Story time',
      starts_at: new Date(Date.now() + 24 * 60 * 60 * 1000).toISOString(),
      location_name: 'Library',
    })
    .select('id')
    .single();
  await poster.admin
    .from('activity_tags')
    .insert({ activity_id: data!.id, tag_id: 'family-friendly' });
  await page.goto(`/activities/${data!.id}`);
  await expect(page.getByText('Family-friendly')).toHaveCount(0);
});
