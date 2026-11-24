// A picture when posting (MEDIA-02): New activity's picture is the activity's cover from the start,
// and a series shows it on every date. The pgTAP tests cover sharing it with a series' dates, and
// pictures.spec.ts covers adding one from the activity's page.
import type { Page } from '@playwright/test';
import { expect, expectAccessible, test } from './fixtures';

// A 1x1 PNG, so the test needs no image file on disk.
const PNG = Buffer.from(
  'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAIAAACQd1PeAAAADUlEQVR42mNkYPhfDwAChwGA60e6kgAAAABJRU5ErkJggg==',
  'base64'
);

/** A photo as big as a phone's, 3000 by 4000 px of noise, as a high-quality JPEG over 2 MB. */
async function phonePhoto(page: Page): Promise<Buffer> {
  const base64 = await page.evaluate(async () => {
    const canvas = document.createElement('canvas');
    canvas.width = 3000;
    canvas.height = 4000;
    const context = canvas.getContext('2d')!;
    const pixels = context.createImageData(canvas.width, canvas.height);
    for (let i = 0; i < pixels.data.length; i++) pixels.data[i] = (i * 2654435761) % 251;
    context.putImageData(pixels, 0, 0);
    const blob = await new Promise<Blob>((resolve) =>
      canvas.toBlob((made) => resolve(made!), 'image/jpeg', 0.95)
    );
    const bytes = new Uint8Array(await blob.arrayBuffer());
    let binary = '';
    for (const byte of bytes) binary += String.fromCharCode(byte);
    return btoa(binary);
  });
  return Buffer.from(base64, 'base64');
}

/** Fills in New activity's required fields, with a title of its own. */
async function fillRequired(page: Page, title: string) {
  await page.getByLabel('What are you doing?').fill(title);
  await page.getByLabel('Start time').fill('19:00');
  await page.getByLabel('Where?').fill('Hart courts');
  await page.getByRole('radio', { name: 'Sports' }).check();
}

const named = (title: string) => `${title} ${crypto.randomUUID().slice(0, 6)}`;

test('a photo chosen while posting is the activity’s cover from the start', async ({
  page,
  poster,
}) => {
  expect(poster.id).toBeTruthy();
  await page.goto('/activities/new');
  const picture = page.getByLabel('A photo for the top of the activity and its card');
  const alt = page.getByLabel("Describe it for people who can't see it");
  // The description is needed only once a picture is chosen.
  await expect(alt).not.toHaveAttribute('required');
  await expectAccessible(page);

  const title = named('Pickleball night');
  await fillRequired(page, title);
  // A phone's photo, over 2 MB, is made smaller on the device first.
  const photo = await phonePhoto(page);
  expect(photo.length).toBeGreaterThan(2 * 1024 * 1024);
  await picture.setInputFiles({ name: 'IMG_0042.jpg', mimeType: 'image/jpeg', buffer: photo });
  await expect(alt).toHaveAttribute('required');
  await alt.fill('Paddles and a ball on the court');
  await page.getByRole('button', { name: 'Post activity' }).click();

  await expect(page).toHaveURL(/\/activities\/[0-9a-f-]{36}$/);
  await expect(page.getByRole('status')).toHaveText('Posted!');
  const cover = page.getByRole('img', { name: 'Paddles and a ball on the court' });
  await expect(cover).toBeVisible();
  // Its medium copy, the whole picture, which the device made, is what a phone shows (UI-27,
  // MEDIA-03).
  await expect
    .poll(() => cover.evaluate((img: HTMLImageElement) => img.currentSrc))
    .toContain('?size=whole');

  // Its card on Discover shows it too.
  await page.goto('/discover');
  await expect(
    page.getByRole('article').filter({ hasText: title }).locator('img[src*="size=thumb"]')
  ).toBeVisible();
});

test('a series posted with a picture shows it on every date', async ({ page, poster }) => {
  await page.goto('/activities/new');
  const title = named('Weekly pickleball');
  await fillRequired(page, title);
  await page.getByText('More options').click();
  await page.getByLabel('How often').selectOption('weekly');
  await page
    .getByLabel('A photo for the top of the activity and its card')
    .setInputFiles({ name: 'court.png', mimeType: 'image/png', buffer: PNG });
  await page.getByLabel("Describe it for people who can't see it").fill('The Hart courts');
  await page.getByRole('button', { name: 'Post activity' }).click();
  await expect(page.getByRole('status')).toHaveText('Posted!');

  // Every date has the one picture.
  const { data: dates } = await poster.admin
    .from('activities')
    .select('id, cover_image_id')
    .eq('title', title)
    .order('starts_at');
  expect(dates!.length).toBeGreaterThan(1);
  expect(new Set(dates!.map(({ cover_image_id }) => cover_image_id)).size).toBe(1);
  expect(dates![0].cover_image_id).toBeTruthy();

  await page.goto(`/activities/${dates!.at(-1)!.id}`);
  await expect(page.getByRole('img', { name: 'The Hart courts' })).toBeVisible();
});

test.describe('without JavaScript', () => {
  test.use({ javaScriptEnabled: false });

  test('a picture that won’t do comes back with the reason, and what was typed', async ({
    page,
    poster,
  }) => {
    await page.goto('/activities/new');
    const title = named('Board game night');
    await fillRequired(page, title);
    const picture = page.getByLabel('A photo for the top of the activity and its card');

    // No description.
    await picture.setInputFiles({ name: 'table.png', mimeType: 'image/png', buffer: PNG });
    await page.getByRole('button', { name: 'Post activity' }).click();
    await expect(
      page.getByLabel("Describe it for people who can't see it")
    ).toHaveAccessibleDescription(/Describe the picture for people who can't see it\.$/);
    await expect(page.getByLabel('What are you doing?')).toHaveValue(title);
    await expect(page.getByText('Choose the picture again to post it.')).toBeVisible();

    // An iPhone's HEIC, which only JavaScript would have made a JPEG.
    await picture.setInputFiles({
      name: 'IMG_0042.HEIC',
      mimeType: 'image/heic',
      buffer: Buffer.from('not really a photo'),
    });
    await page.getByLabel("Describe it for people who can't see it").fill('The game table');
    await page.getByRole('button', { name: 'Post activity' }).click();
    await expect(picture).toHaveAccessibleDescription(/Use a JPEG, PNG or WebP picture\.$/);

    // A file that only says it's a JPEG.
    await picture.setInputFiles({
      name: 'table.jpg',
      mimeType: 'image/jpeg',
      buffer: Buffer.from('not really a photo'),
    });
    await page.getByRole('button', { name: 'Post activity' }).click();
    await expect(page.getByRole('alert').first()).toHaveText('Use a JPEG, PNG or WebP picture.');

    // Nothing was posted.
    const { count } = await poster.admin
      .from('activities')
      .select('id', { count: 'exact', head: true })
      .eq('title', title);
    expect(count).toBe(0);

    // A good one posts, as it is.
    await picture.setInputFiles({ name: 'table.png', mimeType: 'image/png', buffer: PNG });
    await page.getByRole('button', { name: 'Post activity' }).click();
    await expect(page.getByRole('status')).toHaveText('Posted!');
    await expect(page.getByRole('img', { name: 'The game table' })).toBeVisible();
  });
});
