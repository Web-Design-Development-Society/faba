// Muting an activity (NOTIF-08). The pgTAP tests cover which notifications muting holds back.
import { expect, expectAccessible, test } from './fixtures';

test('Mute updates stops changes but not a cancellation, and Unmute undoes it', async ({
  page,
  poster,
  crowd,
}) => {
  const [organizer] = await crowd(1);
  const { data: id } = await organizer.rpc('create_activity', {
    title: 'Board game night',
    category_id: 'games',
    starts_at: new Date(Date.now() + 24 * 60 * 60 * 1000).toISOString(),
    location_name: 'Library',
  });

  // Only those going or maybe can mute, so the menu offers it once Pat is going.
  await page.goto(`/activities/${id}`);
  await page.getByLabel('More actions').click();
  await expect(page.getByRole('button', { name: 'Mute updates' })).toHaveCount(0);
  // ✓ Going shows before the RSVP is saved, so the reload waits for it.
  const saved = page.waitForResponse((response) => response.url().includes('/_actions/rsvps.set'));
  await page.getByRole('button', { name: "I'm in" }).click();
  await expect(page.getByRole('button', { name: '✓ Going' })).toBeVisible();
  expect((await saved).ok()).toBe(true);
  await page.reload();

  await page.getByLabel('More actions').click();
  await page.getByRole('button', { name: 'Mute updates' }).click();
  await expect(page.getByRole('status')).toHaveText("Muted. You'll still hear if it's cancelled.");
  await page.getByLabel('More actions').click();
  await expect(page.getByRole('button', { name: 'Unmute updates' })).toBeVisible();
  await expectAccessible(page);

  const { data: activity } = await organizer
    .from('activities')
    .select('version')
    .eq('id', id!)
    .single();
  await organizer.rpc('update_activity', {
    activity_id: id!,
    patch: { location_name: 'Hart courts' },
    expected_version: activity!.version,
  });
  await organizer.rpc('cancel_activity', { activity_id: id!, reason: 'Snowed in' });
  const { data: notifications } = await poster.admin
    .from('notifications')
    .select('type')
    .eq('recipient_id', poster.id);
  expect(notifications).toEqual([{ type: 'activity_cancelled' }]);

  await page.getByRole('button', { name: 'Unmute updates' }).click();
  await expect(page.getByRole('status')).toHaveText('Unmuted.');
  await page.getByLabel('More actions').click();
  await expect(page.getByRole('button', { name: 'Mute updates' })).toBeVisible();
});
