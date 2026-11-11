// Group updates (GRP-04). The pgTAP tests cover the limits, who reads them, reporting and hiding.
import { expect, expectAccessible, test } from './fixtures';

test("an organizer posts an update, and the group's members hear about it", async ({
  page,
  poster,
  crowd,
}) => {
  const tag = crypto.randomUUID().slice(0, 6);
  const { data: group } = await poster.admin
    .from('groups')
    .insert({
      slug: `hikers-${tag}`,
      name: `Hikers ${tag}`,
      category_id: 'outdoors',
      owner_id: poster.id,
    })
    .select('id, slug')
    .single();
  await poster.admin
    .from('group_members')
    .insert({ group_id: group!.id, user_id: poster.id, role: 'owner' });
  const [member] = await crowd(1);
  await member.rpc('join_group', { group_id: group!.id });

  await page.goto(`/groups/${group!.slug}`);
  await page.getByRole('link', { name: 'Post update' }).click();
  await expect(page).toHaveURL(`/groups/${group!.slug}/update`);
  await expectAccessible(page);
  await page.getByLabel('Update').fill('  Trail is muddy, bring boots.  ');
  await page.getByRole('button', { name: 'Post update' }).click();

  await expect(page).toHaveURL(`/groups/${group!.slug}#updates`);
  await expect(page.getByRole('status')).toHaveText('Update posted.');
  const updates = page.getByRole('region', { name: 'Updates' });
  await expect(updates.getByRole('listitem')).toHaveCount(1);
  await expect(updates.getByRole('listitem')).toContainText('Trail is muddy, bring boots.');
  await expect(updates.getByRole('link', { name: 'Report' })).toHaveCount(0);
  await expectAccessible(page);

  const { data: notifications } = await member.from('notifications').select('type, group_id');
  expect(notifications).toEqual([{ type: 'group_update', group_id: group!.id }]);
});
