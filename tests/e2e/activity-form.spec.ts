// The New activity form's layout (UI-06). Each project runs at its own width, so this checks a
// 320 px iPhone SE, a 412 px Pixel and a desktop. create-activity.spec.ts covers posting.
import { expect, expectAccessible, test } from './fixtures';

const BLUE = 'rgb(11, 91, 211)';
const WHITE = 'rgb(255, 255, 255)';

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
    (await page.getByLabel('Date').boundingBox())!,
    (await page.getByLabel('Start time').boundingBox())!,
  ];
  if (page.viewportSize()!.width < 360) expect(time.y).toBeGreaterThan(date.y + date.height - 1);
  else expect(Math.abs(time.y - date.y)).toBeLessThanOrEqual(2);

  // The quick dates are outlined chips, not filled buttons.
  await expect(page.getByRole('button', { name: 'Tomorrow' })).toHaveCSS('background-color', WHITE);

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
