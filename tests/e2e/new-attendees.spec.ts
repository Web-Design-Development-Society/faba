// New people going, for organizers (NOTIF-06). The pgTAP tests cover the hourly batch, starting
// again once read, and muting.
import { expect, expectAccessible, test } from './fixtures';

test('the organizer gets one alert for new people going', async ({ page, poster, crowd }) => {
  const { data: activity } = await poster.admin
    .from('activities')
    .insert({
      organizer_id: poster.id,
      category_id: 'sports',
      title: 'Pickleball',
      starts_at: new Date(Date.now() + 24 * 60 * 60 * 1000).toISOString(),
      location_name: 'Hart courts',
      going_count: 1,
    })
    .select('id')
    .single();
  await poster.admin
    .from('rsvps')
    .insert({ activity_id: activity!.id, user_id: poster.id, status: 'going' });
  const members = await crowd(3);
  for (const member of members) {
    await member.rpc('rsvp', { activity_id: activity!.id, status: 'going' });
  }

  await page.goto('/notifications');
  const alerts = page
    .getByRole('navigation', { name: 'Main' })
    .getByRole('link', { name: /^Alerts/ });
  await expect(alerts).toHaveAccessibleName('Alerts 1 unread');
  await expect(page.getByRole('region', { name: 'New' }).getByRole('button')).toHaveText([
    /Unread: 3 new people are going\s*Pickleball/,
  ]);
  await expectAccessible(page);

  await page.getByRole('button', { name: /3 new people are going/ }).click();
  await expect(page).toHaveURL(`/activities/${activity!.id}`);
});
