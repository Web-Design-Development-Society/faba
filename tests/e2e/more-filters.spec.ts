// More filters (SRCH-03). Discover has other tests' activities too, so this searches for a word only
// its own activities have, where More filters work the same. The pgTAP tests cover the filters.
import { expect, expectAccessible, test } from './fixtures';

test('Has spots left and a tag combine, and Clear all takes them off', async ({
  page,
  signInAs,
  host,
}) => {
  await signInAs('member');
  const tag = `w${crypto.randomUUID().slice(0, 8)}`;
  // Hana takes the picnic's only spot.
  const picnic = await host.post({ title: `Free picnic ${tag}`, capacity: 1 });
  const games = await host.post({ title: `Free games ${tag}` });
  await host.post({ title: `Paid lunch ${tag}` });
  await host.admin.from('activity_tags').insert([
    { activity_id: picnic, tag_id: 'free' },
    { activity_id: games, tag_id: 'free' },
  ]);

  await page.goto(`/search?q=${tag}`);
  await page.getByRole('button', { name: 'More filters' }).click();
  const sheet = page.getByRole('dialog', { name: 'More filters' });
  await sheet.getByLabel('Has spots left').check();
  await sheet.getByRole('group', { name: 'Tags' }).getByLabel('Free').check();
  await expectAccessible(page);
  await sheet.getByRole('button', { name: 'Apply' }).click();

  await expect(page).toHaveURL(`/search?q=${tag}&spots=1&tag=free`);
  await expect(page.getByText(`Free games ${tag}`)).toBeVisible();
  await expect(page.getByText(`Free picnic ${tag}`)).toHaveCount(0);
  await expect(page.getByText(`Paid lunch ${tag}`)).toHaveCount(0);
  await expect(page.getByRole('button', { name: 'More filters (2)' })).toBeVisible();

  await page.getByRole('button', { name: 'More filters (2)' }).click();
  await sheet.getByRole('link', { name: 'Clear all' }).click();
  await expect(page).toHaveURL(`/search?q=${tag}`);
  await expect(page.getByText(`Paid lunch ${tag}`)).toBeVisible();
});
