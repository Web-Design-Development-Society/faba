// Activity cards that show the time and place (UI-03). Each project runs at its own width, so this
// checks a 320 px iPhone SE, a 412 px Pixel and a desktop.
import type { Locator } from '@playwright/test';
import { formatSoon } from '../../src/lib/time';
import { expect, expectAccessible, test } from './fixtures';

const HOUR = 60 * 60 * 1000;
const BLUE = 'rgb(11, 91, 211)';
// Other tests post at the same time, so each activity has a title of its own.
const named = (title: string) => `${title} ${crypto.randomUUID().slice(0, 8)}`;
// Intl's spaces before AM and PM differ between Node and the Worker.
const loosely = (text: string) => new RegExp(text.replace(/\s/g, '\\s'));

/** The right edge of `inner` is inside `outer`'s, so nothing is cut off at the card's edge. */
async function inside(inner: Locator, outer: Locator) {
  const [a, b] = [(await inner.boundingBox())!, (await outer.boundingBox())!];
  expect(a.x + a.width).toBeLessThanOrEqual(b.x + b.width + 0.5);
}

test('a card shows the whole time, the place on one line, and I’m in under them', async ({
  page,
  signInAs,
  host,
}) => {
  await signInAs('member');
  const title = named('Hiking – Hidden Valley');
  const startsAt = new Date(Date.now() + 2 * HOUR);
  await host.post({
    title,
    starts_at: startsAt.toISOString(),
    location_name: 'Hidden Valley Park, north trailhead parking lot by the river',
  });

  await page.goto('/discover');
  const card = page.getByRole('article').filter({ hasText: title });
  const time = card.getByText(loosely(formatSoon(startsAt, new Date())));
  await expect(time).toBeVisible();
  await inside(time, card);
  // The time is on one line.
  const lines = await time.evaluate((el) => el.getClientRects().length);
  expect(lines).toBe(1);

  // A long place ends with an ellipsis, on one line, inside the card.
  const place = card.getByText(/^Hidden Valley Park, north/);
  await inside(place, card);
  expect(await place.evaluate((el) => el.scrollWidth > el.clientWidth)).toBe(true);

  // I'm in is under the time and place, not squeezing them from the side.
  const button = card.getByRole('button', { name: "I'm in" });
  const [placeBox, buttonBox] = [(await place.boundingBox())!, (await button.boundingBox())!];
  expect(buttonBox.y).toBeGreaterThanOrEqual(placeBox.y + placeBox.height - 1);

  // The title has room for words, not one word to a line.
  const heading = card.getByRole('heading', { name: title });
  expect((await heading.boundingBox())!.width).toBeGreaterThan(110);

  // Nothing is wider than the screen.
  expect(await page.evaluate(() => document.documentElement.scrollWidth <= window.innerWidth)).toBe(
    true
  );
  await expectAccessible(page);
});

test('your next plan has a blue edge', async ({ page, poster, host }) => {
  const title = named('Disc golf');
  const id = await host.post({
    title,
    category_id: 'sports',
    starts_at: new Date(Date.now() + 3 * HOUR).toISOString(),
  });
  await host.admin.from('rsvps').insert({ activity_id: id, user_id: poster.id, status: 'going' });

  await page.goto('/discover');
  const plan = page.getByRole('region', { name: 'Your next plan' }).getByRole('article');
  await expect(plan).toContainText(title);
  await expect(plan).toHaveCSS('border-left-color', BLUE);
});

test("a card shows its cover's small copy", async ({ page, poster }) => {
  const title = named('Picture picnic');
  const { data } = await poster.admin
    .from('activities')
    .insert({
      organizer_id: poster.id,
      category_id: 'food',
      title,
      starts_at: new Date(Date.now() + 4 * HOUR).toISOString(),
      location_name: 'Porter Park',
    })
    .select('id')
    .single();

  // A 600 by 400 picture, drawn in the page, so the test needs no file on disk.
  await page.goto(`/activities/${data!.id}`);
  const base64 = await page.evaluate(async () => {
    const canvas = Object.assign(document.createElement('canvas'), { width: 600, height: 400 });
    const context = canvas.getContext('2d')!;
    context.fillStyle = '#2e7d32';
    context.fillRect(0, 0, 600, 400);
    const blob = await new Promise<Blob>((resolve) =>
      canvas.toBlob((made) => resolve(made!), 'image/png')
    );
    const bytes = new Uint8Array(await blob.arrayBuffer());
    return btoa(String.fromCharCode(...bytes));
  });
  await page.getByLabel('Picture (JPEG, PNG or WebP)').setInputFiles({
    name: 'picnic.png',
    mimeType: 'image/png',
    buffer: Buffer.from(base64, 'base64'),
  });
  await page.getByLabel("Describe it for people who can't see it").fill('A green field');
  await page.getByRole('button', { name: 'Save picture' }).click();
  await expect(page.getByRole('status')).toHaveText('Picture saved. It shows on the activity.');

  await page.goto('/discover');
  const card = page.getByRole('article').filter({ hasText: title });
  // The picture stands for the category, as the icon did.
  const picture = card.getByRole('img', { name: 'Food & Socials' }).locator('img');
  await expect(picture).toHaveAttribute('src', /\?size=thumb$/);
  // It loads when it's near the screen.
  await picture.scrollIntoViewIfNeeded();
  await expect.poll(() => picture.evaluate((img: HTMLImageElement) => img.naturalWidth)).toBe(320);
});
