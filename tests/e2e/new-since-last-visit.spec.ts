// New since your last visit (ACT-11). The pgTAP tests cover when a visit starts and ends.
import { expect, test } from './fixtures';

test('Home marks what others posted since the last visit, and keeps it while browsing', async ({
  page,
  poster,
  host,
}) => {
  const hourAgo = new Date(Date.now() - 60 * 60 * 1000).toISOString();
  await poster.admin
    .from('profile_private')
    .update({ last_seen_at: hourAgo })
    .eq('user_id', poster.id);
  const tag = crypto.randomUUID().slice(0, 8);
  const older = await host.post({ title: `Older hike ${tag}` });
  await host.admin
    .from('activities')
    .update({ created_at: new Date(Date.now() - 2 * 60 * 60 * 1000).toISOString() })
    .eq('id', older);
  await host.post({ title: `Newer hike ${tag}` });

  const card = (title: string) => page.getByRole('article').filter({ hasText: title });
  for (let visit = 0; visit < 2; visit++) {
    await page.goto('/discover');
    await expect(card(`Newer hike ${tag}`).getByRole('listitem')).toHaveText(['New']);
    await expect(card(`Older hike ${tag}`).getByRole('listitem')).toHaveCount(0);
  }
});

test('a first visit marks nothing', async ({ page, poster, host }) => {
  expect(poster.id).toBeTruthy();
  const tag = crypto.randomUUID().slice(0, 8);
  await host.post({ title: `Hike ${tag}` });
  await page.goto('/discover');
  await expect(
    page
      .getByRole('article')
      .filter({ hasText: `Hike ${tag}` })
      .getByRole('listitem')
  ).toHaveCount(0);
});
