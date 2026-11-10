// Reporting and hiding organizer updates (NOTIF-04, FR-REP-3). The pgTAP tests cover who can report,
// hide and read them, and the audit log.
import { expect, expectAccessible, test } from './fixtures';

test('a member reports an update', async ({ page, poster, host }) => {
  const id = await host.post();
  const { data: update } = await host.admin
    .from('activity_updates')
    .insert({ activity_id: id, author_id: host.id, body: 'Cheap tickets at example.com' })
    .select('id')
    .single();

  await page.goto(`/activities/${id}`);
  await page.getByRole('region', { name: 'Updates' }).getByRole('link', { name: 'Report' }).click();
  await expect(page).toHaveURL(`/activities/${id}/updates/${update!.id}/report`);
  await expect(page.getByText('Cheap tickets at example.com')).toBeVisible();
  await expectAccessible(page);
  await page.getByLabel('Spam / commercial').check();
  await page.getByRole('button', { name: 'Send report' }).click();

  await expect(page).toHaveURL(`/activities/${id}#updates`);
  await expect(page.getByRole('status')).toHaveText('Thanks, a moderator will review this.');
  const { data: reports } = await poster.admin
    .from('reports')
    .select('target_type, reason')
    .eq('reporter_id', poster.id);
  expect(reports).toEqual([{ target_type: 'activity_update', reason: 'spam' }]);
});

test('a moderator hides a reported update, and unhides it', async ({
  page,
  signInAs,
  host,
  crowd,
}) => {
  await signInAs('moderator');
  const tag = crypto.randomUUID().slice(0, 8);
  const id = await host.post({ title: `Hike ${tag}` });
  const { data: update } = await host.admin
    .from('activity_updates')
    .insert({ activity_id: id, author_id: host.id, body: `Tickets ${tag} at example.com` })
    .select('id')
    .single();
  // From someone who has since deleted their account, so it outlives the test's members.
  const { data: report } = await host.admin
    .from('reports')
    .insert({
      reporter_id: null,
      target_type: 'activity_update',
      target_id: update!.id,
      reason: 'spam',
    })
    .select('id')
    .single();
  try {
    await page.goto('/mod');
    const reported = page.getByRole('article').filter({ hasText: `Tickets ${tag}` });
    await expect(reported).toContainText(`Update to Hike ${tag}`);
    await expectAccessible(page);
    await reported.getByRole('button', { name: 'Hide update' }).click();
    const sheet = page.getByRole('dialog', { name: 'Hide this update?' });
    await sheet.getByLabel('Reason, for the audit log').fill('Selling tickets');
    await sheet.getByRole('button', { name: 'Hide update' }).click();
    await expect(page.getByRole('status')).toHaveText('Update hidden.');
    await expect(reported).toHaveCount(0);

    const [member] = await crowd(1);
    const { data: seen } = await member.from('activity_updates').select('id').eq('activity_id', id);
    expect(seen).toEqual([]);

    await page.goto(`/activities/${id}`);
    const updates = page.getByRole('region', { name: 'Updates' });
    await expect(updates).toContainText('Hidden by a moderator: Selling tickets');
    await updates.getByRole('button', { name: 'Unhide update' }).click();
    const unhide = page.getByRole('dialog', { name: 'Unhide this update?' });
    await unhide.getByLabel('Reason, for the audit log').fill('Organizer explained');
    await unhide.getByRole('button', { name: 'Yes, unhide it' }).click();
    await expect(page.getByRole('status')).toHaveText('Update unhidden.');
    await expect(updates).not.toContainText('Hidden by a moderator');
    await expect(updates).toContainText(`Tickets ${tag}`);
  } finally {
    await host.admin.from('reports').delete().eq('id', report!.id);
  }
});

test("the organizer sees why their update was hidden, and can't report it", async ({
  page,
  poster,
}) => {
  const { data: activity } = await poster.admin
    .from('activities')
    .insert({
      organizer_id: poster.id,
      category_id: 'games',
      title: 'Board game night',
      starts_at: new Date(Date.now() + 24 * 60 * 60 * 1000).toISOString(),
      location_name: 'Library',
    })
    .select('id')
    .single();
  await poster.admin.from('activity_updates').insert({
    activity_id: activity!.id,
    author_id: poster.id,
    body: 'Bring snacks',
    hidden_at: new Date().toISOString(),
    hidden_reason: 'Off topic',
  });

  await page.goto(`/activities/${activity!.id}`);
  const updates = page.getByRole('region', { name: 'Updates' });
  await expect(updates).toContainText('Hidden by a moderator: Off topic');
  await expect(updates).toContainText('Bring snacks');
  await expect(updates.getByRole('link', { name: 'Report' })).toHaveCount(0);
  await expect(updates.getByRole('button', { name: 'Unhide update' })).toHaveCount(0);
  await expectAccessible(page);
});
