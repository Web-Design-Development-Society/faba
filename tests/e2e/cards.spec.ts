// Activity cards (UI-03, UI-17): the title, a picture and the time and place on white paper, and the
// date and the member's answer in a blue column. Each project runs at its own width, so this checks a
// 320 px iPhone SE, a 412 px Pixel and a desktop.
import type { Locator } from '@playwright/test';
import { soonParts } from '../../src/lib/time';
import { expect, expectAccessible, test } from './fixtures';

const HOUR = 60 * 60 * 1000;
// Other tests post at the same time, so each activity has a title of its own.
const named = (title: string) => `${title} ${crypto.randomUUID().slice(0, 8)}`;
// Intl's spaces before AM and PM differ between Node and the Worker.
const loosely = (text: string) => new RegExp(text.replace(/\s/g, '\\s'));

/** The right edge of `inner` is inside `outer`'s, so nothing is cut off at the card's edge. */
async function inside(inner: Locator, outer: Locator) {
  const [a, b] = [(await inner.boundingBox())!, (await outer.boundingBox())!];
  expect(a.x + a.width).toBeLessThanOrEqual(b.x + b.width + 0.5);
}

test('a card has its title, picture, time and place on paper, and its date and I’m in on blue', async ({
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
  const box = (await card.boundingBox())!;

  // The title across the top, bigger than before UI-17, with room for words.
  const heading = card.getByRole('heading', { name: title });
  const size = (locator: Locator) =>
    locator.evaluate((el) => parseFloat(getComputedStyle(el).fontSize));
  expect(await size(heading)).toBeGreaterThanOrEqual(24);
  expect((await heading.boundingBox())!.width).toBeGreaterThan(110);

  // The picture under it, bigger too.
  const picture = card.getByRole('img', { name: 'Outdoors' });
  const pictureBox = (await picture.boundingBox())!;
  expect(pictureBox.width).toBeGreaterThanOrEqual(72);
  expect(pictureBox.y).toBeGreaterThan((await heading.boundingBox())!.y);

  // The day and time beside it, big, with no icon. A narrow phone may break the line between the
  // day and the time, but never inside either.
  const [day, clock] = soonParts(startsAt, new Date());
  const time = card.locator('time');
  await expect(time).toHaveText(loosely(`${day} ${clock}`));
  expect(await size(time)).toBeGreaterThanOrEqual(18);
  expect((await time.boundingBox())!.x).toBeGreaterThan(pictureBox.x + pictureBox.width);
  for (const part of await time.locator('span').all()) {
    expect(await part.evaluate((el) => el.getClientRects().length)).toBe(1);
  }
  await inside(time, card);
  await expect(card.locator('.rows svg')).toHaveCount(0);

  // A long place ends with an ellipsis, on one line, inside the card.
  const place = card.getByText(/^Hidden Valley Park, north/);
  await inside(place, card);
  expect(await place.evaluate((el) => el.scrollWidth > el.clientWidth)).toBe(true);

  // Who's going is just the count, and there's no chevron.
  await expect(card.getByText('1 going', { exact: true })).toBeVisible();
  await expect(card.locator('.avatar, .chevron')).toHaveCount(0);

  // A FABA blue column, at the right and as tall as the card, with the date at the top and I'm in,
  // white with FABA blue text, at the bottom.
  const side = card.locator('.side');
  const sideBox = (await side.boundingBox())!;
  await expect(side).toHaveCSS('background-color', 'rgb(0, 108, 194)');
  expect(Math.abs(sideBox.x + sideBox.width - (box.x + box.width))).toBeLessThanOrEqual(1.5);
  expect(Math.abs(sideBox.height - box.height)).toBeLessThanOrEqual(2.5);
  expect(sideBox.x).toBeGreaterThan((await place.boundingBox())!.x);
  const date = side.locator('.date');
  const boise = (options: Intl.DateTimeFormatOptions) =>
    new Intl.DateTimeFormat('en-US', { ...options, timeZone: 'America/Boise' }).format(startsAt);
  const [month, dayOfMonth] = [boise({ month: 'short' }).toUpperCase(), boise({ day: 'numeric' })];
  await expect(date).toHaveText(new RegExp(`^${month}\\s*${dayOfMonth}$`));
  const button = side.getByRole('button', { name: "I'm in" });
  await expect(button).toHaveCSS('background-color', 'rgb(255, 255, 255)');
  await expect(button).toHaveCSS('color', 'rgb(0, 108, 194)');
  const [dateBox, buttonBox] = [(await date.boundingBox())!, (await button.boundingBox())!];
  expect(buttonBox.y).toBeGreaterThan(dateBox.y + dateBox.height);
  expect(buttonBox.height).toBeGreaterThanOrEqual(44);

  // Nothing is wider than the screen.
  expect(await page.evaluate(() => document.documentElement.scrollWidth <= window.innerWidth)).toBe(
    true
  );
  await expectAccessible(page);
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

  // A 1200 by 800 picture, drawn in the page, so the test needs no file on disk.
  await page.goto(`/activities/${data!.id}`);
  const base64 = await page.evaluate(async () => {
    const canvas = Object.assign(document.createElement('canvas'), { width: 1200, height: 800 });
    const context = canvas.getContext('2d')!;
    context.fillStyle = '#2e7d32';
    context.fillRect(0, 0, 1200, 800);
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
  await expect.poll(() => picture.evaluate((img: HTMLImageElement) => img.naturalWidth)).toBe(640);
});
