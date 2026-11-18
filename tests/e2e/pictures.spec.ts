// Pictures for activities and groups (MEDIA-01), and their medium copies for phones (UI-27). The
// pgTAP tests cover who can set and hide them, and the unit tests cover the file checks and sizes.
import type { Locator, Page } from '@playwright/test';
import { expect, expectAccessible, test } from './fixtures';

// A 1x1 PNG, so the test needs no image file on disk.
const PNG = Buffer.from(
  'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAIAAACQd1PeAAAADUlEQVR42mNkYPhfDwAChwGA60e6kgAAAABJRU5ErkJggg==',
  'base64'
);
const TWO_MB = 2 * 1024 * 1024;

async function makeActivity(poster: {
  id: string;
  admin: import('@supabase/supabase-js').SupabaseClient;
}) {
  const { data } = await poster.admin
    .from('activities')
    .insert({
      organizer_id: poster.id,
      category_id: 'games',
      title: `Picture night ${crypto.randomUUID().slice(0, 6)}`,
      starts_at: new Date(Date.now() + 24 * 60 * 60 * 1000).toISOString(),
      location_name: 'Library',
    })
    .select('id')
    .single();
  return data!.id as string;
}

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

/** The width and height of the picture at `src`, as the browser reads it. */
function sizeOf(page: Page, src: string) {
  return page.evaluate(async (url) => {
    const img = new Image();
    img.src = url;
    await img.decode();
    return [img.naturalWidth, img.naturalHeight];
  }, src);
}

/** The picture fits the page's width at this shape, width over height. */
async function expectShape(page: Page, picture: Locator, shape: number) {
  const box = (await picture.boundingBox())!;
  const page_ = await page.evaluate(() => document.body.clientWidth);
  expect(box.width).toBeLessThanOrEqual(page_);
  expect(Math.abs(box.height - box.width / shape)).toBeLessThanOrEqual(1);
}

test('an organizer adds a cover picture to an activity, and it shows on the page', async ({
  page,
  poster,
}) => {
  const id = await makeActivity(poster);

  await page.goto(`/activities/${id}`);
  await page.getByLabel('Picture (JPEG, PNG or WebP)').setInputFiles({
    name: 'cover.png',
    mimeType: 'image/png',
    buffer: PNG,
  });
  await page.getByLabel("Describe it for people who can't see it").fill('A small test square');
  await page.getByRole('button', { name: 'Save picture' }).click();
  await expect(page.getByRole('status')).toHaveText('Picture saved. It shows on the activity.');
  await expect(page.getByRole('img', { name: 'A small test square' })).toBeVisible();
  await expectAccessible(page);
});

test('a photo from a phone is made smaller on the device, and saves', async ({ page, poster }) => {
  const id = await makeActivity(poster);
  await page.goto(`/activities/${id}`);
  const photo = await phonePhoto(page);
  expect(photo.length).toBeGreaterThan(TWO_MB);

  await page.getByLabel('Picture (JPEG, PNG or WebP)').setInputFiles({
    name: 'IMG_0042.jpg',
    mimeType: 'image/jpeg',
    buffer: photo,
  });
  await page.getByLabel("Describe it for people who can't see it").fill('The game table');
  await page.getByRole('button', { name: 'Save picture' }).click();
  await expect(page.getByRole('status')).toHaveText('Picture saved. It shows on the activity.');
  const picture = page.getByRole('img', { name: 'The game table' });
  await expect(picture).toBeVisible();
  // The page shows its medium copy: the middle of the photo at the page's 16:9, 1080 px wide,
  // since the page is narrower than that on every screen the tests use (UI-27). It waits for the picture to load, then measures
  // the file it loaded, since srcset makes naturalWidth the width it's shown at.
  await expect
    .poll(() => picture.evaluate((img: HTMLImageElement) => img.currentSrc))
    .toContain('?size=medium');
  const shown = await picture.evaluate((img: HTMLImageElement) => img.currentSrc);
  expect(await sizeOf(page, shown)).toEqual([1080, 608]);
  // The full picture is at most 1600 px on its longest side.
  const full = (await picture.getAttribute('src'))!.replace('?size=medium', '');
  expect(await sizeOf(page, full)).toEqual([1200, 1600]);
  // The tall photo shows across the page at 16:9, not as tall as the screen.
  await expectShape(page, picture, 16 / 9);
  const { data: saved } = await poster.admin
    .from('images')
    .select('content_type, bytes')
    .eq('alt', 'The game table')
    .single();
  expect(saved!.content_type).toBe('image/jpeg');
  expect(saved!.bytes).toBeLessThanOrEqual(TWO_MB);
});

test("a group's banner shows as a wide strip across the page", async ({ page, poster }) => {
  const tag = crypto.randomUUID().slice(0, 6);
  const { data: group } = await poster.admin
    .from('groups')
    .insert({
      slug: `bakers-${tag}`,
      name: `Bakers ${tag}`,
      category_id: 'food',
      owner_id: poster.id,
    })
    .select('id, slug')
    .single();
  await poster.admin
    .from('group_members')
    .insert({ group_id: group!.id, user_id: poster.id, role: 'owner' });

  await page.goto(`/groups/${group!.slug}`);
  await page.getByText('Change the banner').click();
  await page.getByLabel('Picture (JPEG, PNG or WebP)').setInputFiles({
    name: 'IMG_0043.jpg',
    mimeType: 'image/jpeg',
    buffer: await phonePhoto(page),
  });
  await page.getByLabel("Describe it for people who can't see it").fill('Loaves on a table');
  await page.getByRole('button', { name: 'Save banner' }).click();
  const banner = page.getByRole('img', { name: 'Loaves on a table' });
  await expect(banner).toBeVisible();
  await expectShape(page, banner, 3);
  // Its medium copy too (UI-27).
  await expect
    .poll(() => banner.evaluate((img: HTMLImageElement) => img.currentSrc))
    .toContain('?size=medium');
  const shown = await banner.evaluate((img: HTMLImageElement) => img.currentSrc);
  expect(await sizeOf(page, shown)).toEqual([1080, 360]);
  await expectAccessible(page);
});

test("a picture that hasn't changed isn't sent again", async ({ page, poster }) => {
  const id = await makeActivity(poster);
  await page.goto(`/activities/${id}`);
  await page.getByLabel('Picture (JPEG, PNG or WebP)').setInputFiles({
    name: 'cover.png',
    mimeType: 'image/png',
    buffer: PNG,
  });
  await page.getByLabel("Describe it for people who can't see it").fill('A tiny square');
  await page.getByRole('button', { name: 'Save picture' }).click();
  const src = (await page.getByRole('img', { name: 'A tiny square' }).getAttribute('src'))!;
  const full = src.replace('?size=medium', '');

  // The browser keeps it for 5 minutes, so a hidden one goes quickly (UI-27).
  const first = await page.request.get(full);
  expect(first.status()).toBe(200);
  expect(first.headers()['cache-control']).toBe('private, max-age=300');
  const etag = first.headers()['etag'];
  expect(etag).toBeTruthy();
  // After that, a copy that's still current hears "not changed", with no picture.
  const again = await page.request.get(full, { headers: { 'If-None-Match': etag } });
  expect(again.status()).toBe(304);
  expect((await again.body()).length).toBe(0);
  // Its medium copy is a file of its own, answered the same way.
  const medium = await page.request.get(src);
  const mediumTag = medium.headers()['etag'];
  expect(mediumTag).not.toBe(etag);
  const mediumAgain = await page.request.get(src, { headers: { 'If-None-Match': mediumTag } });
  expect(mediumAgain.status()).toBe(304);
  // Once a moderator hides it, it's gone, even for a copy that was current.
  await poster.admin
    .from('images')
    .update({ hidden_at: new Date().toISOString() })
    .eq('alt', 'A tiny square');
  const hidden = await page.request.get(full, { headers: { 'If-None-Match': etag } });
  expect(hidden.status()).toBe(404);
});

test('a file that is not a picture is refused, and the form says why', async ({ page, poster }) => {
  const id = await makeActivity(poster);

  await page.goto(`/activities/${id}`);
  await page.getByLabel('Picture (JPEG, PNG or WebP)').setInputFiles({
    name: 'notes.txt',
    mimeType: 'text/plain',
    buffer: Buffer.from('not a picture'),
  });
  await page.getByLabel("Describe it for people who can't see it").fill('Notes');
  await page.getByRole('button', { name: 'Save picture' }).click();
  await expect(page).toHaveURL(`/activities/${id}#picture`);
  const form = page.locator('form#picture');
  await expect(form.getByRole('alert')).toHaveText('Use a JPEG, PNG or WebP picture.');
  await expect(form.getByRole('alert')).toBeInViewport();
  await expect(page.getByLabel('Picture (JPEG, PNG or WebP)')).toHaveAccessibleDescription(
    /Use a JPEG, PNG or WebP picture\./
  );
  // Not a toast that goes, at the other end of the page.
  await expect(page.getByRole('status')).toHaveText('');
  await expectAccessible(page);
});

test.describe('without JavaScript', () => {
  test.use({ javaScriptEnabled: false });

  test('a picture over 2 MB is refused, and the form says why', async ({ page, poster }) => {
    const id = await makeActivity(poster);

    await page.goto(`/activities/${id}`);
    // A PNG's first bytes, then enough to pass 2 MB. Only the size and first bytes are checked.
    const big = Buffer.concat([PNG.subarray(0, 8), Buffer.alloc(TWO_MB + 1)]);
    await page.getByLabel('Picture (JPEG, PNG or WebP)').setInputFiles({
      name: 'big.png',
      mimeType: 'image/png',
      buffer: big,
    });
    await page.getByLabel("Describe it for people who can't see it").fill('Too big');
    await page.getByRole('button', { name: 'Save picture' }).click();
    await expect(page.locator('form#picture').getByRole('alert')).toHaveText(
      'Use a picture under 2 MB.'
    );
  });
});
