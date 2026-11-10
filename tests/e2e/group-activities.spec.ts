// Group activities and who sees them (GRP-03). The pgTAP tests cover RLS for members, others,
// requests, moderators, search, RSVPs and announcements.
import { expect, expectAccessible, test } from './fixtures';

test('an organizer posts an activity for their group members only', async ({
  page,
  poster,
  crowd,
}) => {
  const tag = crypto.randomUUID().slice(0, 6);
  const { data: group } = await poster.admin
    .from('groups')
    .insert({
      slug: `runners-${tag}`,
      name: `Runners ${tag}`,
      category_id: 'outdoors',
      owner_id: poster.id,
    })
    .select('id, slug')
    .single();
  await poster.admin
    .from('group_members')
    .insert({ group_id: group!.id, user_id: poster.id, role: 'owner' });
  const [member, outsider] = await crowd(2);
  const { data: memberId } = await member.rpc('join_group', { group_id: group!.id });
  expect(memberId).toBe('active');

  await page.goto(`/groups/${group!.slug}`);
  await expect(page.getByText('Nothing planned yet.')).toBeVisible();
  await page.getByRole('link', { name: 'Post an activity' }).click();
  await expect(page.getByLabel('Post under a group you organize (optional)')).toHaveValue(
    group!.id
  );
  await page.getByLabel('What are you doing?').fill('Members-only tempo run');
  await page.getByLabel('Start time').fill('18:00');
  await page.getByLabel('Where?').fill('Track');
  await page.getByRole('radio', { name: 'Outdoors' }).check();
  await page.getByRole('radio', { name: 'Group members only' }).check();
  await expectAccessible(page);
  await page.getByRole('button', { name: 'Post activity' }).click();

  await expect(page.getByRole('status')).toHaveText('Posted!');
  await expect(page.getByText(`Runners ${tag} · Group members only`)).toBeVisible();
  const id = page.url().split('/').pop()!;

  const { data: seen } = await member.from('activities').select('title').eq('id', id);
  expect(seen).toEqual([{ title: 'Members-only tempo run' }]);
  const { data: hidden } = await outsider.from('activities').select('title').eq('id', id);
  expect(hidden).toEqual([]);

  await page.goto(`/groups/${group!.slug}`);
  await expect(
    page.getByRole('article').filter({ hasText: 'Members-only tempo run' })
  ).toBeVisible();
});

test('the Group choice is only for members who organize a group', async ({ page, poster }) => {
  expect(poster.id).toBeTruthy();
  await page.goto('/activities/new');
  await expect(page.getByRole('group', { name: 'Group' })).toHaveCount(0);
});
