// Organizer updates to attendees (NOTIF-04). The pgTAP tests cover who's told, the daily limit and
// who can read updates.
import { expect, expectAccessible, test } from './fixtures';

const tomorrow = () => new Date(Date.now() + 24 * 60 * 60 * 1000).toISOString();

test('the organizer posts an update, which the people going read', async ({
  page,
  poster,
  crowd,
}) => {
  const { data: activity } = await poster.admin
    .from('activities')
    .insert({
      organizer_id: poster.id,
      category_id: 'outdoors',
      title: 'Sunrise hike',
      starts_at: tomorrow(),
      location_name: 'R Mountain trailhead',
      going_count: 1,
    })
    .select('id')
    .single();
  await poster.admin
    .from('rsvps')
    .insert({ activity_id: activity!.id, user_id: poster.id, status: 'going' });
  const [member] = await crowd(1);
  await member.rpc('rsvp', { activity_id: activity!.id, status: 'going' });

  await page.goto(`/activities/${activity!.id}`);
  await page.getByRole('link', { name: 'Post update' }).click();
  await expect(page).toHaveURL(`/activities/${activity!.id}/update`);
  await expectAccessible(page);
  await page.getByLabel('Update').fill('  Bring a headlamp!  ');
  await page.getByRole('button', { name: 'Post update' }).click();

  await expect(page).toHaveURL(`/activities/${activity!.id}#updates`);
  await expect(page.getByRole('status')).toHaveText('Update posted.');
  const updates = page.getByRole('region', { name: 'Updates' });
  await expect(updates.getByRole('listitem')).toHaveCount(1);
  await expect(updates.getByRole('listitem')).toContainText('Pat Poster');
  await expect(updates.getByRole('listitem')).toContainText('Bring a headlamp!');
  await expectAccessible(page);

  const { data: notifications } = await member.from('notifications').select('type');
  expect(notifications).toEqual([{ type: 'organizer_update' }]);
});

test('Alerts shows an update, and that it is gone once hidden', async ({ page, poster, host }) => {
  const id = await host.post();
  const { data: update } = await host.admin
    .from('activity_updates')
    .insert({ activity_id: id, author_id: host.id, body: 'Parking is at the trailhead.' })
    .select('id')
    .single();
  await poster.admin.from('notifications').insert({
    recipient_id: poster.id,
    type: 'organizer_update',
    activity_id: id,
    actor_id: host.id,
    payload: { update_id: update!.id, title: 'Sunrise hike up the R' },
  });

  await page.goto('/notifications');
  await expect(page.getByText('Hana Host: Parking is at the trailhead.')).toBeVisible();
  await expectAccessible(page);

  await host.admin
    .from('activity_updates')
    .update({ hidden_at: new Date().toISOString() })
    .eq('id', update!.id);
  await page.reload();
  await expect(page.getByText('This update is no longer available')).toBeVisible();
  await expect(page.getByText('Parking is at the trailhead.')).toHaveCount(0);
});

test('a post that fails keeps what was typed', async ({ page, poster }) => {
  const { data: activity } = await poster.admin
    .from('activities')
    .insert({
      organizer_id: poster.id,
      category_id: 'games',
      title: 'Board game night',
      starts_at: tomorrow(),
      location_name: 'Library',
    })
    .select('id')
    .single();
  await poster.admin.from('activity_updates').insert(
    Array.from({ length: 5 }, (_, n) => ({
      activity_id: activity!.id,
      author_id: poster.id,
      body: `Update ${n + 1}`,
    }))
  );

  await page.goto(`/activities/${activity!.id}/update`);
  await page.getByLabel('Update').fill('One more thing');
  await page.getByRole('button', { name: 'Post update' }).click();
  await expect(page.getByRole('alert')).toHaveText(
    'You can post up to 5 updates a day to an activity. Try again tomorrow.'
  );
  await expect(page.getByLabel('Update')).toHaveValue('One more thing');
});

test('only the organizer can post an update', async ({ page, poster, host }) => {
  void poster;
  const id = await host.post();

  await page.goto(`/activities/${id}`);
  await expect(page.getByRole('link', { name: 'Post update' })).toHaveCount(0);
  await page.goto(`/activities/${id}/update`);
  await expect(
    page.getByText('Only the organizer can post updates to this activity.')
  ).toBeVisible();
});
