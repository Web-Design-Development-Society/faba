// A group's members, listed on its page (UI-23), and managing them and its organizers from the
// Manage members sheet (GRP-05). The pgTAP tests cover who can do what, removing members,
// moderators and the audit log.
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

  // "1 asking to join" opens the sheet.
  await page.goto(`/groups/${group!.slug}`);
  await page.getByRole('button', { name: '1 asking to join' }).click();
  const sheet = page.getByRole('dialog', { name: 'Manage members' });
  await expect(sheet.getByRole('region', { name: 'Asking to join' })).toContainText(
    'Crowd Member 1'
  );
  await expectAccessible(page);

  await sheet.getByRole('button', { name: 'Approve Crowd Member 1' }).click();
  await expect(page.getByRole('status')).toHaveText("Approved. They're in the group.");
  await expect(page).toHaveURL(`/groups/${group!.slug}#members`);
  await expect(page.getByRole('button', { name: /asking to join/ })).toHaveCount(0);
  const members = page.getByRole('region', { name: 'Members' });
  await expect(members.getByRole('link', { name: 'Crowd Member 1' })).toBeVisible();
  const { data: notifications } = await member.from('notifications').select('type, group_id');
  expect(notifications).toEqual([{ type: 'group_join_approved', group_id: group!.id }]);

  await page.getByRole('button', { name: 'Manage members' }).click();
  await expect(sheet.getByRole('region', { name: 'Asking to join' })).toHaveCount(0);
  await sheet.getByRole('button', { name: 'Make organizer: Crowd Member 1' }).click();
  await expect(page.getByRole('status')).toHaveText("They're an organizer now.");
  await expect(members.getByRole('listitem').filter({ hasText: 'Crowd Member 1' })).toContainText(
    'Organizer'
  );

  await page.getByRole('button', { name: 'Manage members' }).click();
  await sheet.getByRole('link', { name: 'Hand on this group' }).click();
  await expect(page).toHaveURL(`/groups/${group!.slug}/owner`);
  await expectAccessible(page);
  await page.getByLabel('Crowd Member 1').check();
  await page.getByRole('button', { name: 'Make them the owner' }).click();

  await expect(page).toHaveURL(`/groups/${group!.slug}`);
  await expect(page.getByRole('status')).toHaveText('New owner set.');
  await expect(members.getByRole('listitem').first()).toContainText('Crowd Member 1');
  await expect(members.getByRole('listitem').first()).toContainText('Owner');
  // Pat organizes it now, so manages members but can't hand it on.
  await page.getByRole('button', { name: 'Manage members' }).click();
  await expect(sheet).toBeVisible();
  await expect(sheet.getByRole('link', { name: 'Hand on this group' })).toHaveCount(0);
  const { data: owned } = await member.from('groups').select('owner_id').eq('id', group!.id);
  const {
    data: { user: them },
  } = await member.auth.getUser();
  expect(owned).toEqual([{ owner_id: them!.id }]);
});

test('members see who is in a group on its page, and anyone else only how many', async ({
  page,
  poster,
  crowd,
}) => {
  expect(poster.id).toBeTruthy();
  const [owner, other] = await crowd(2);
  const name = `Painters ${crypto.randomUUID().slice(0, 6)}`;
  const { data: slug } = await owner.rpc('create_group', { name, category_id: 'arts' });
  const { data: group } = await owner.from('groups').select('id').eq('slug', slug!).single();
  await other.rpc('join_group', { group_id: group!.id });

  // Outside it, just the count, as plain words.
  await page.goto(`/groups/${slug}`);
  await expect(page.getByText('2 members ·')).toBeVisible();
  await expect(page.getByRole('link', { name: /members/ })).toHaveCount(0);
  await expect(page.getByRole('region', { name: 'Members' })).toHaveCount(0);

  // In it, everyone, the owner first, with no Manage members for a member.
  await page.getByRole('button', { name: 'Join', exact: true }).click();
  const members = page.getByRole('region', { name: 'Members' });
  await expect(members.getByRole('listitem')).toHaveCount(3);
  await expect(members.getByRole('listitem').first()).toContainText('Crowd Member 1');
  await expect(members.getByRole('listitem').first()).toContainText('Owner');
  await expect(members.getByRole('link', { name: 'Pat Poster' })).toHaveAttribute(
    'href',
    `/people/${poster.id}?from=${encodeURIComponent(`/groups/${slug}`)}`
  );
  await expect(page.getByRole('button', { name: 'Manage members' })).toHaveCount(0);
  await expectAccessible(page);

  // The old address comes here.
  await page.goto(`/groups/${slug}/members`);
  await expect(page).toHaveURL(`/groups/${slug}#members`);
});
