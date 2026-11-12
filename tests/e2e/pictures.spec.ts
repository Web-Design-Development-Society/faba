// Pictures for activities and groups (MEDIA-01). The pgTAP tests cover who can set and hide them, and
// the unit tests cover the file checks. Written while E2E is paused; not yet run.
import { expect, expectAccessible, test } from './fixtures';

// A 1x1 PNG, so the test needs no image file on disk.
const PNG = Buffer.from(
  'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAIAAACQd1PeAAAADUlEQVR42mNkYPhfDwAChwGA60e6kgAAAABJRU5ErkJggg==',
  'base64'
);

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

test('an organizer adds a cover picture to an activity, and it shows on the page', async ({
  page,
  poster,
}) => {
  const id = await makeActivity(poster);

  await page.goto(`/activities/${id}`);
  await page.getByLabel('Picture (JPEG, PNG or WebP, under 2 MB)').setInputFiles({
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

test('a file that is not a picture is refused', async ({ page, poster }) => {
  const id = await makeActivity(poster);

  await page.goto(`/activities/${id}`);
  await page.getByLabel('Picture (JPEG, PNG or WebP, under 2 MB)').setInputFiles({
    name: 'notes.txt',
    mimeType: 'text/plain',
    buffer: Buffer.from('not a picture'),
  });
  await page.getByLabel("Describe it for people who can't see it").fill('Notes');
  await page.getByRole('button', { name: 'Save picture' }).click();
  await expect(page.getByRole('status')).toHaveText('Use a JPEG, PNG or WebP picture.');
});
