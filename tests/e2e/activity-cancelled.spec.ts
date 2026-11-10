// Telling attendees when an activity is cancelled or back on (NOTIF-03). The pgTAP tests cover who's
// told, including moderators' cancels and deleted accounts.
import { expect, test } from './fixtures';

test('cancelling and restoring notify the people going', async ({ page, poster, crowd }) => {
  const { data: activity } = await poster.admin
    .from('activities')
    .insert({
      organizer_id: poster.id,
      category_id: 'games',
      title: 'Board game night',
      starts_at: new Date(Date.now() + 24 * 60 * 60 * 1000).toISOString(),
      location_name: 'Library',
      going_count: 1,
    })
    .select('id')
    .single();
  await poster.admin
    .from('rsvps')
    .insert({ activity_id: activity!.id, user_id: poster.id, status: 'going' });
  const [member] = await crowd(1);
  await member.rpc('rsvp', { activity_id: activity!.id, status: 'going' });

  await page.goto(`/activities/${activity!.id}/edit`);
  await page.getByRole('button', { name: 'Cancel activity' }).click();
  const sheet = page.getByRole('dialog', { name: 'Cancel this activity?' });
  await sheet.getByLabel('Reason (optional)').fill('Snowed in');
  await sheet.getByRole('button', { name: 'Yes, cancel it' }).click();
  await expect(page.getByRole('status')).toHaveText('Cancelled.');
  await page.getByRole('link', { name: 'Edit', exact: true }).click();
  await page.getByRole('button', { name: 'Restore activity' }).click();
  await expect(page.getByRole('status')).toHaveText("Restored. It's back on.");

  const { data } = await member
    .from('notifications')
    .select('type, payload')
    .neq('type', 'rsvp_confirmed')
    .order('created_at')
    .order('type');
  expect(data).toEqual([
    {
      type: 'activity_cancelled',
      payload: expect.objectContaining({ title: 'Board game night', reason: 'Snowed in' }),
    },
    {
      type: 'activity_restored',
      payload: expect.objectContaining({ title: 'Board game night' }),
    },
  ]);
});

test('the center gives the reason', async ({ page, poster }) => {
  await poster.admin.from('notifications').insert({
    recipient_id: poster.id,
    type: 'activity_cancelled',
    payload: { title: 'Sunrise hike', reason: 'Snowed in' },
  });
  await page.goto('/notifications');
  await expect(page.getByText('Cancelled: Snowed in')).toBeVisible();
});
