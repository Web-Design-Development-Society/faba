// A profile photo (UI-11): uploading one, seeing it wherever the member's face is, and removing it.
// The pgTAP tests cover who reads it, replacing it, and a moderator hiding it.
import { expect, expectAccessible, test } from './fixtures';

test('a member adds a photo, sees it everywhere, and removes it', async ({
  page,
  poster,
  host,
}) => {
  // Something Pat is going to, so their face is on its card.
  const title = `Board games ${crypto.randomUUID().slice(0, 6)}`;
  const id = await host.post({
    title,
    category_id: 'games',
    starts_at: new Date(Date.now() + 2 * 60 * 60 * 1000).toISOString(),
  });
  await host.admin.from('rsvps').insert({ activity_id: id, user_id: poster.id, status: 'going' });

  // An 800 by 800 photo, drawn in the page, so the test needs no file on disk.
  await page.goto('/me/edit');
  const base64 = await page.evaluate(async () => {
    const canvas = Object.assign(document.createElement('canvas'), { width: 800, height: 800 });
    const context = canvas.getContext('2d')!;
    context.fillStyle = '#0b5bd3';
    context.fillRect(0, 0, 800, 800);
    const blob = await new Promise<Blob>((resolve) =>
      canvas.toBlob((made) => resolve(made!), 'image/png')
    );
    const bytes = new Uint8Array(await blob.arrayBuffer());
    return btoa(String.fromCharCode(...bytes));
  });
  // The test accounts have a photo from Google, which shows until one is uploaded.
  const appearance = page.getByRole('group', { name: 'How you appear' });
  await expect(appearance.getByRole('radio', { name: 'My Google photo' })).toBeChecked();
  await expect(page.getByRole('img', { name: 'Pat Poster' })).not.toHaveAttribute(
    'src',
    /^\/api\/media\//
  );

  await page.getByText('Add a photo').click();
  // A face needs no description: it's the member's name.
  await expect(page.getByLabel("Describe it for people who can't see it")).toHaveCount(0);
  await expectAccessible(page);
  await page.getByLabel('Photo (JPEG, PNG or WebP)').setInputFiles({
    name: 'me.png',
    mimeType: 'image/png',
    buffer: Buffer.from(base64, 'base64'),
  });
  await page.getByRole('button', { name: 'Save photo' }).click();
  await expect(page.getByRole('status')).toHaveText(
    'Photo saved. It shows wherever your face does.'
  );
  const photo = page.getByRole('img', { name: 'Pat Poster' });
  await expect(photo).toHaveAttribute('src', /^\/api\/media\/[0-9a-f-]{36}\?size=thumb$/);
  // Its small copy, made for faces.
  await expect.poll(() => photo.evaluate((img: HTMLImageElement) => img.naturalWidth)).toBe(256);
  await expect(appearance.getByRole('radio', { name: 'My photo' })).toBeChecked();

  // On Me, and on the card of what Pat's going to.
  await page.goto('/me');
  await expect(page.getByRole('img', { name: 'Pat Poster' })).toHaveAttribute(
    'src',
    /^\/api\/media\//
  );
  await page.goto('/discover');
  const card = page.getByRole('article').filter({ hasText: title }).first();
  await expect(card.getByRole('img', { name: 'Pat Poster' })).toHaveAttribute(
    'src',
    /^\/api\/media\//
  );

  // Removing it goes back to the Google photo.
  await page.goto('/me/edit');
  await page.getByRole('button', { name: 'Remove photo' }).click();
  await expect(page.getByRole('status')).toHaveText('Photo removed.');
  await expect(page.getByRole('img', { name: 'Pat Poster' })).not.toHaveAttribute(
    'src',
    /^\/api\/media\//
  );
  await expect(appearance.getByRole('radio', { name: 'My Google photo' })).toBeChecked();
  await expect(page.getByRole('button', { name: 'Remove photo' })).toHaveCount(0);
});
