// Group cards in Discover → Groups (UI-10). Each project runs at its own width, so this checks a
// 320 px iPhone SE, a 412 px Pixel and a desktop.
import { expect, expectAccessible, test } from './fixtures';

// Other tests make groups at the same time, so each has a name of its own.
const named = (name: string) => `${name} ${crypto.randomUUID().slice(0, 6)}`;
const slugOf = (name: string) => name.toLowerCase().replace(/[^a-z0-9]+/g, '-');

test('each group is a card with its picture and the basics', async ({ page, poster, host }) => {
  // One the member owns, and a league they've asked to join.
  const hikers = named('Hikers');
  const { data: mine } = await poster.admin
    .from('groups')
    .insert({
      slug: slugOf(hikers),
      name: hikers,
      category_id: 'outdoors',
      owner_id: poster.id,
      description: 'Saturday morning hikes around Rexburg, all paces welcome.',
    })
    .select('id, slug')
    .single();
  await poster.admin
    .from('group_members')
    .insert({ group_id: mine!.id, user_id: poster.id, role: 'owner' });
  const league = named('Pickleball league');
  const { data: theirs } = await host.admin
    .from('groups')
    .insert({
      slug: slugOf(league),
      name: league,
      category_id: 'sports',
      kind: 'league',
      join_policy: 'approval',
      owner_id: host.id,
    })
    .select('id')
    .single();
  await host.admin.from('group_members').insert([
    { group_id: theirs!.id, user_id: host.id, role: 'owner' },
    { group_id: theirs!.id, user_id: poster.id, status: 'pending' },
  ]);

  await page.goto('/groups');
  const card = page.getByRole('article').filter({ hasText: hikers });
  // No banner yet, so the category's strip, labeled with its name.
  await expect(card.getByRole('img', { name: 'Outdoors', exact: true })).toBeVisible();
  await expect(card.getByRole('heading', { name: hikers })).toBeVisible();
  await expect(card.getByRole('listitem')).toHaveText([
    "You're in",
    'Outdoors',
    '1 member',
    'Anyone can join',
  ]);
  await expect(card.getByText('Saturday morning hikes')).toBeVisible();

  const other = page.getByRole('article').filter({ hasText: league });
  await expect(other.getByRole('listitem')).toHaveText([
    'Requested',
    'League',
    'Sports & Fitness',
    '1 member',
    'Ask to join',
  ]);

  expect(await page.evaluate(() => document.documentElement.scrollWidth <= window.innerWidth)).toBe(
    true
  );
  await expectAccessible(page);

  // The whole card opens the group, not just its name.
  await card.getByText('Anyone can join').click();
  await expect(page).toHaveURL(`/groups/${mine!.slug}`);
});

test("a group's banner shows across its card, from its small copy", async ({ page, poster }) => {
  const bakers = named('Bakers');
  const { data: group } = await poster.admin
    .from('groups')
    .insert({ slug: slugOf(bakers), name: bakers, category_id: 'food', owner_id: poster.id })
    .select('id, slug')
    .single();
  await poster.admin
    .from('group_members')
    .insert({ group_id: group!.id, user_id: poster.id, role: 'owner' });

  // A 1500 by 500 banner, drawn in the page, so the test needs no file on disk.
  await page.goto(`/groups/${group!.slug}`);
  const base64 = await page.evaluate(async () => {
    const canvas = Object.assign(document.createElement('canvas'), { width: 1500, height: 500 });
    const context = canvas.getContext('2d')!;
    context.fillStyle = '#e65100';
    context.fillRect(0, 0, 1500, 500);
    const blob = await new Promise<Blob>((resolve) =>
      canvas.toBlob((made) => resolve(made!), 'image/png')
    );
    const bytes = new Uint8Array(await blob.arrayBuffer());
    return btoa(String.fromCharCode(...bytes));
  });
  await page.getByText('Change the banner').click();
  await page.getByLabel('Picture (JPEG, PNG or WebP)').setInputFiles({
    name: 'banner.png',
    mimeType: 'image/png',
    buffer: Buffer.from(base64, 'base64'),
  });
  await page.getByLabel("Describe it for people who can't see it").fill('Loaves on a table');
  await page.getByRole('button', { name: 'Save banner' }).click();
  await expect(page.getByRole('img', { name: 'Loaves on a table' })).toBeVisible();

  await page.goto('/groups');
  const card = page.getByRole('article').filter({ hasText: bakers });
  const picture = card.getByRole('img', { name: 'Food & Socials', exact: true }).locator('img');
  await expect(picture).toHaveAttribute('src', /\?size=thumb$/);
  await picture.scrollIntoViewIfNeeded();
  await expect.poll(() => picture.evaluate((img: HTMLImageElement) => img.naturalWidth)).toBe(640);
  // Across the card, at 3:1.
  const [box, cardBox] = [(await picture.boundingBox())!, (await card.boundingBox())!];
  expect(Math.abs(box.width - cardBox.width)).toBeLessThanOrEqual(2);
  expect(Math.abs(box.height - box.width / 3)).toBeLessThanOrEqual(1);
});
