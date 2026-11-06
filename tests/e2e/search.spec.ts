// Searching activities by keyword (SRCH-01). Other tests post at the same time, so each searches for
// a word only its own activity has. The pgTAP tests cover what matches.
import { expect, expectAccessible, test } from './fixtures';

const word = () => `w${crypto.randomUUID().slice(0, 8)}`;

test('a member finds an activity by part of a word, from Discover', async ({
  page,
  signInAs,
  host,
}) => {
  await signInAs('member');
  const tag = word();
  const title = `Lunch pickleball ${tag}`;
  await host.post({ title });

  await page.goto('/discover');
  await page.getByRole('link', { name: 'Search' }).click();
  const field = page.getByLabel('Search activities');
  await expect(field).toBeFocused();
  await field.fill(`${tag} pickle`);
  await field.press('Enter');
  await expect(page).toHaveURL(`/search?q=${tag}+pickle`);
  await expect(page.getByText(title)).toBeVisible();
  await expectAccessible(page);
});

test('past activities show with Include past', async ({ page, signInAs, host }) => {
  await signInAs('member');
  const tag = word();
  const title = `Board game night ${tag}`;
  const id = await host.post({ title });
  const lastWeek = new Date(Date.now() - 7 * 24 * 60 * 60 * 1000).toISOString();
  await host.admin.from('activities').update({ starts_at: lastWeek }).eq('id', id);

  await page.goto(`/search?q=${tag}`);
  await expect(page.getByText(`Nothing coming up matches ${tag}.`)).toBeVisible();
  await page.getByLabel('Include past').check();
  await expect(page).toHaveURL(`/search?q=${tag}&past=1`);
  await expect(page.getByText(title)).toBeVisible();
});

test("the organizer's name matches, and recent searches stay on the device", async ({
  page,
  signInAs,
  host,
}) => {
  await signInAs('member');
  const tag = word();
  const title = `Sunrise hike ${tag}`;
  await host.post({ title });

  await page.goto(`/search?q=${encodeURIComponent(`Hana Host ${tag}`)}`);
  await expect(page.getByText(title)).toBeVisible();

  await page.goto('/search');
  const recent = page.getByRole('region', { name: 'Recent searches' });
  await recent.getByRole('link', { name: `Hana Host ${tag}` }).click();
  await expect(page.getByText(title)).toBeVisible();
  await expectAccessible(page);
});

test.describe('without JavaScript', () => {
  test.use({ javaScriptEnabled: false });

  test('search still works', async ({ page, signInAs, host }) => {
    await signInAs('member');
    const tag = word();
    const title = `Watercolor class ${tag}`;
    await host.post({ title });

    await page.goto('/search');
    await page.getByLabel('Search activities').fill(tag);
    await page.getByRole('button', { name: 'Search' }).click();
    await expect(page.getByText(title)).toBeVisible();
  });
});
