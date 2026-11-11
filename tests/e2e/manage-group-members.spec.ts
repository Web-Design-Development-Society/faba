// Managing a group's members and organizers (GRP-05). The pgTAP tests cover who can do what,
// removing members, moderators and the audit log.
import { expect, expectAccessible, test } from './fixtures';

test('the owner approves a request, makes an organizer, and hands the group on', async ({
  page,
  poster,
  crowd,
}) => {
  const tag = crypto.randomUUID().slice(0, 6);
  const { data: group } = await poster.admin
    .from('groups')
    .insert({
      slug: `quilters-${tag}`,
      name: `Quilters ${tag}`,
      category_id: 'arts',
      join_policy: 'approval',
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
  await page.getByRole('link', { name: '1 asking to join' }).click();
  await expect(page).toHaveURL(`/groups/${group!.slug}/members`);
  await expect(page.getByRole('region', { name: 'Asking to join' })).toContainText(
    'Crowd Member 1'
  );
  await expectAccessible(page);

  await page.getByRole('button', { name: 'Approve Crowd Member 1' }).click();
  await expect(page.getByRole('status')).toHaveText("Approved. They're in the group.");
  await expect(page.getByRole('region', { name: 'Asking to join' })).toHaveCount(0);
  const { data: notifications } = await member.from('notifications').select('type, group_id');
  expect(notifications).toEqual([{ type: 'group_join_approved', group_id: group!.id }]);

  await page.getByRole('button', { name: 'Make Crowd Member 1 an organizer' }).click();
  await expect(page.getByRole('status')).toHaveText("They're an organizer now.");
  await expect(page.getByRole('region', { name: 'Organizers' })).toContainText('Crowd Member 1');

  await page.getByRole('link', { name: 'Hand on this group' }).click();
  await expect(page).toHaveURL(`/groups/${group!.slug}/owner`);
  await expectAccessible(page);
  await page.getByLabel('Crowd Member 1').check();
  await page.getByRole('button', { name: 'Make them the owner' }).click();

  await expect(page).toHaveURL(`/groups/${group!.slug}/members`);
  await expect(page.getByRole('status')).toHaveText('New owner set.');
  await expect(page.getByRole('link', { name: 'Hand on this group' })).toHaveCount(0);
  const { data: owned } = await member.from('groups').select('owner_id').eq('id', group!.id);
  const {
    data: { user: them },
  } = await member.auth.getUser();
  expect(owned).toEqual([{ owner_id: them!.id }]);
});
