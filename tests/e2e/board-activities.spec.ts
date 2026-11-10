// Board activities and announcements (MOD-07). Announcing tells every member in the database, which
// would reach other tests' members while they run, so this stops at the sheet. The pgTAP tests
// cover announcing, who's told, and the audit log.
import { expect, expectAccessible, test } from './fixtures';

test('an admin marks their activity as a board activity, and the card and page say so', async ({
  page,
  poster,
}) => {
  await poster.admin.from('profiles').update({ role: 'admin' }).eq('id', poster.id);
  const { data: activity } = await poster.admin
    .from('activities')
    .insert({
      organizer_id: poster.id,
      category_id: 'food',
      title: 'Welcome back social',
      starts_at: new Date(Date.now() + 2 * 24 * 60 * 60 * 1000).toISOString(),
      location_name: 'Hart ballroom',
      going_count: 1,
    })
    .select('id')
    .single();
  await poster.admin
    .from('rsvps')
    .insert({ activity_id: activity!.id, user_id: poster.id, status: 'going' });

  await page.goto(`/activities/${activity!.id}`);
  await page.getByLabel('More actions').click();
  await expect(page.getByRole('button', { name: 'Announce to every member' })).toHaveCount(0);
  await page.getByRole('button', { name: 'Mark as board activity' }).click();
  await expect(page.getByRole('status')).toHaveText('Marked as a board activity.');
  await expect(page.getByText('FABA board activity')).toBeVisible();
  await expectAccessible(page);

  await page.goto('/plans?show=organizing');
  await expect(
    page.getByRole('article').filter({ hasText: 'Welcome back social' }).getByRole('listitem')
  ).toHaveText(['Board activity']);
});

test('the announce sheet warns after 2 announcements in 30 days', async ({ page, poster }) => {
  await poster.admin.from('profiles').update({ role: 'admin' }).eq('id', poster.id);
  const soon = new Date(Date.now() + 2 * 24 * 60 * 60 * 1000).toISOString();
  const { data: activities } = await poster.admin
    .from('activities')
    .insert(
      ['Welcome back social', 'Spring social', 'Fall social'].map((title, i) => ({
        organizer_id: poster.id,
        category_id: 'food',
        title,
        starts_at: soon,
        location_name: 'Hart ballroom',
        is_board_activity: true,
        announced_at: i > 0 ? new Date().toISOString() : null,
      }))
    )
    .select('id, title');
  const id = activities!.find(({ title }) => title === 'Welcome back social')!.id;

  await page.goto(`/activities/${id}`);
  await page.getByLabel('More actions').click();
  await page.getByRole('button', { name: 'Announce to every member' }).click();
  const sheet = page.getByRole('dialog', { name: 'Announce to every member?' });
  await expect(sheet).toContainText('Every active member gets it in Alerts.');
  await expect(sheet).toContainText(/The board has sent \d+ announcements in the last 30 days/);
  await expectAccessible(page);
  await sheet.getByRole('button', { name: 'Not now' }).click();
  await expect(sheet).toBeHidden();
});

test('members see the badge, but not the board options', async ({ page, poster, host }) => {
  expect(poster.id).toBeTruthy();
  const id = await host.post({ title: 'Welcome back social' });
  await host.admin.from('activities').update({ is_board_activity: true }).eq('id', id);

  await page.goto(`/activities/${id}`);
  await expect(page.getByText('FABA board activity')).toBeVisible();
  await page.getByLabel('More actions').click();
  await expect(page.getByRole('button', { name: /board activity/ })).toHaveCount(0);
  await expect(page.getByRole('button', { name: 'Announce to every member' })).toHaveCount(0);
});
