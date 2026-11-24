// Pictures for activities and groups (MEDIA-01), their medium copies for phones (UI-27), and a
// cover shown whole (MEDIA-03). The pgTAP tests cover who can set and hide them, and the unit tests
// cover the file checks and sizes.
import type { Locator, Page } from '@playwright/test';
import { crc32, deflateSync } from 'node:zlib';
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

/**
 * A photo of noise as a high-quality JPEG: by default as big as a phone's, 3000 by 4000 px and over
 * 2 MB.
 */
async function phonePhoto(page: Page, width = 3000, height = 4000): Promise<Buffer> {
  const base64 = await page.evaluate(
    async ([width, height]) => {
      const canvas = document.createElement('canvas');
      canvas.width = width;
      canvas.height = height;
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
    },
    [width, height]
  );
  return Buffer.from(base64, 'base64');
}

/** A gray `width` by `height` PNG, made here, for a test without JavaScript. */
function grayPng(width: number, height: number): Buffer {
  const chunk = (type: string, data: Buffer) => {
    const body = Buffer.concat([Buffer.from(type, 'ascii'), data]);
    const length = Buffer.alloc(4);
    length.writeUInt32BE(data.length);
    const sum = Buffer.alloc(4);
    sum.writeUInt32BE(crc32(body));
    return Buffer.concat([length, body, sum]);
  };
  const header = Buffer.alloc(13);
  header.writeUInt32BE(width, 0);
  header.writeUInt32BE(height, 4);
  header[8] = 8; // 8 bits a channel
  header[9] = 2; // red, green and blue
  // Each row starts with its filter, none.
  const row = Buffer.concat([Buffer.from([0]), Buffer.alloc(width * 3, 0x80)]);
  return Buffer.concat([
    Buffer.from([0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a]),
    chunk('IHDR', header),
    chunk('IDAT', deflateSync(Buffer.concat(Array(height).fill(row)))),
    chunk('IEND', Buffer.alloc(0)),
  ]);
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

/** The light theme's paper, which an activity's page is on (UI-26). */
const PAPER = 'rgb(247, 244, 236)';

/**
 * The cover shows the whole picture, of this shape, across the page (MEDIA-03): as tall as it needs,
 * up to 24rem or half the screen, with the page's paper beside a tall one. Its box is as wide as the
 * page, and the picture is drawn whole inside it. It reads no styles with the page's own scripts,
 * so it works without JavaScript too.
 */
async function expectWhole(page: Page, picture: Locator, shape: number) {
  await expect(picture).toHaveCSS('object-fit', 'contain');
  await expect(page.locator('main')).toHaveCSS('background-color', PAPER);
  await expect(picture).toHaveCSS('background-color', PAPER);
  const across = (await picture.locator('..').boundingBox())!.width;
  const limit = Math.min(24 * 16, page.viewportSize()!.height / 2);
  // Until the picture loads, its box is 16:9.
  await expect
    .poll(async () => {
      const box = (await picture.boundingBox())!;
      return [
        Math.abs(box.width - across) <= 1,
        Math.abs(box.height - Math.min(box.width / shape, limit)) <= 1,
      ];
    })
    .toEqual([true, true]);
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
  // The page shows its medium copy: the whole photo, 1080 px tall (MEDIA-03), since the page is
  // narrower than that on every screen the tests use (UI-27). It waits for the picture to load, then
  // measures the file it loaded, since srcset makes naturalWidth the width it's shown at.
  await expect
    .poll(() => picture.evaluate((img: HTMLImageElement) => img.currentSrc))
    .toContain('?size=whole');
  const shown = await picture.evaluate((img: HTMLImageElement) => img.currentSrc);
  expect(await sizeOf(page, shown)).toEqual([810, 1080]);
  // The full picture is at most 1600 px on its longest side.
  const full = (await picture.getAttribute('src'))!.replace('?size=whole', '');
  expect(await sizeOf(page, full)).toEqual([1200, 1600]);
  // The tall photo shows whole, as tall as the limit, not as tall as the screen, with the page's
  // paper beside it.
  await expectWhole(page, picture, 3 / 4);
  const box = (await picture.boundingBox())!;
  expect(box.height * (3 / 4)).toBeLessThan(box.width - 16);
  const { data: saved } = await poster.admin
    .from('images')
    .select('content_type, bytes')
    .eq('alt', 'The game table')
    .single();
  expect(saved!.content_type).toBe('image/jpeg');
  expect(saved!.bytes).toBeLessThanOrEqual(TWO_MB);
});

test('a wide photo spans the page, with nothing beside it', async ({ page, poster }) => {
  const id = await makeActivity(poster);
  await page.goto(`/activities/${id}`);
  await page.getByLabel('Picture (JPEG, PNG or WebP)').setInputFiles({
    name: 'IMG_0044.jpg',
    mimeType: 'image/jpeg',
    buffer: await phonePhoto(page, 1600, 900),
  });
  await page.getByLabel("Describe it for people who can't see it").fill('The whole team');
  await page.getByRole('button', { name: 'Save picture' }).click();
  const picture = page.getByRole('img', { name: 'The whole team' });
  await expect
    .poll(() => picture.evaluate((img: HTMLImageElement) => img.currentSrc))
    .toContain('?size=whole');
  const shown = await picture.evaluate((img: HTMLImageElement) => img.currentSrc);
  expect(await sizeOf(page, shown)).toEqual([1080, 608]);
  // Its box is its own shape, so the paper never shows.
  await expectWhole(page, picture, 16 / 9);
  await expectShape(page, picture, 16 / 9);
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
  const full = src.replace('?size=whole', '');

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

test.describe('without JavaScript', () => {
  test.use({ javaScriptEnabled: false });

  test('a cover with no copy of its own, like one added before MEDIA-03, shows its full picture whole', async ({
    page,
    poster,
  }) => {
    const id = await makeActivity(poster);
    await page.goto(`/activities/${id}`);
    const tall = grayPng(300, 400);
    await page.getByLabel('Picture (JPEG, PNG or WebP)').setInputFiles({
      name: 'flyer.png',
      mimeType: 'image/png',
      buffer: tall,
    });
    await page.getByLabel("Describe it for people who can't see it").fill('The flyer');
    await page.getByRole('button', { name: 'Save picture' }).click();
    const picture = page.getByRole('img', { name: 'The flyer' });
    await expect(picture).toBeVisible();

    // The page asks for the whole copy, which it doesn't have, so it gets the full picture.
    const src = (await picture.getAttribute('src'))!;
    expect(src).toContain('?size=whole');
    expect(Buffer.from(await (await page.request.get(src)).body())).toEqual(tall);
    await expectWhole(page, picture, 3 / 4);
  });
});
