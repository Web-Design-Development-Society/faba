// Joining and leaving groups (GRP-02). The pgTAP tests cover the counts, archived and hidden groups,
// the owner, and who reads what.
import { expect, test } from './fixtures';

test('a member joins an open group in one tap, and leaves it', async ({ page, poster, crowd }) => {
  expect(poster.id).toBeTruthy();
  const [owner] = await crowd(1);
  const name = `Runners ${crypto.randomUUID().slice(0, 6)}`;
  const { data: slug } = await owner.rpc('create_group', { name, category_id: 'outdoors' });

  await page.goto(`/groups/${slug}`);
  await expect(page.getByText('1 member ·')).toBeVisible();
  await page.getByRole('button', { name: 'Join', exact: true }).click();
  await expect(page.getByRole('status')).toHaveText("You're in the group.");
  await expect(page.getByText("✓ You're a member")).toBeVisible();
  await expect(page.getByText('2 members ·')).toBeVisible();

  await page.getByRole('button', { name: 'Leave group' }).click();
  await expect(page.getByRole('status')).toHaveText('You left the group.');
  await expect(page.getByRole('button', { name: 'Join', exact: true })).toBeVisible();
});

test('asking to join an approval group tells its owner', async ({ page, poster, crowd }) => {
  expect(poster.id).toBeTruthy();
  const [owner] = await crowd(1);
  const name = `Quilters ${crypto.randomUUID().slice(0, 6)}`;
  const { data: slug } = await owner.rpc('create_group', {
    name,
    category_id: 'arts',
    join_policy: 'approval',
  });

  await page.goto(`/groups/${slug}`);
  await page.getByRole('button', { name: 'Request to join' }).click();
  await expect(page.getByRole('status')).toHaveText(
    "Request sent. You're in once an organizer approves it."
  );
  await expect(page.getByText('1 member ·')).toBeVisible();

  const { data } = await owner.from('notifications').select('type, payload');
  expect(data).toEqual([
    {
      type: 'group_join_request',
      payload: expect.objectContaining({ name, member: 'Pat Poster' }),
    },
  ]);

  await page.getByRole('button', { name: 'Withdraw request' }).click();
  await expect(page.getByRole('status')).toHaveText('Request withdrawn.');
  const { data: after } = await owner.from('notifications').select('type');
  expect(after).toEqual([]);
});
