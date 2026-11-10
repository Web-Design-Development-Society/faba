// Telling attendees about a new time, place or details for attendees (NOTIF-02). The pgTAP tests
// cover who's told and edits within 10 minutes.
import { expect, test } from './fixtures';

test('a new start time notifies the people going', async ({ page, poster, crowd }) => {
  // On the minute, as the edit form saves it, so only the place changes.
  const tomorrow = new Date(Date.now() + 24 * 60 * 60 * 1000);
  tomorrow.setSeconds(0, 0);
  const { data: activity } = await poster.admin
    .from('activities')
    .insert({
      organizer_id: poster.id,
      category_id: 'games',
      title: 'Board game night',
      starts_at: tomorrow.toISOString(),
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
  await page.getByLabel('Where?').fill('Hart courts');
  await page.getByRole('button', { name: 'Save' }).click();
  await expect(page.getByRole('status')).toHaveText('Saved.');

  const { data } = await member
    .from('notifications')
    .select('type, payload')
    .neq('type', 'rsvp_confirmed');
  expect(data).toEqual([
    {
      type: 'activity_changed',
      payload: expect.objectContaining({
        title: 'Board game night',
        before: expect.objectContaining({ location_name: 'Library' }),
        after: expect.objectContaining({ location_name: 'Hart courts' }),
      }),
    },
  ]);
});

test('new details for attendees tell the people going, but not what they are', async ({
  page,
  poster,
  crowd,
}) => {
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
  await page.getByLabel('Details for attendees only').fill('Gate code 4521');
  await page.getByRole('button', { name: 'Save' }).click();
  await expect(page.getByRole('status')).toHaveText('Saved.');

  const { data } = await member
    .from('notifications')
    .select('type, payload')
    .neq('type', 'rsvp_confirmed');
  expect(data).toEqual([
    {
      type: 'activity_changed',
      payload: expect.objectContaining({ title: 'Board game night', details_changed: true }),
    },
  ]);
  expect(JSON.stringify(data)).not.toContain('4521');
});

test('the center says what changed', async ({ page, poster }) => {
  await poster.admin.from('notifications').insert({
    recipient_id: poster.id,
    type: 'activity_changed',
    payload: {
      title: 'Board game night',
      before: { starts_at: '2026-12-04T19:00:00-07:00', location_name: 'Library' },
      after: { starts_at: '2026-12-04T19:30:00-07:00', location_name: 'Library' },
    },
  });
  await poster.admin.from('notifications').insert({
    recipient_id: poster.id,
    type: 'activity_changed',
    payload: {
      title: 'Board game night',
      before: { starts_at: '2026-12-04T19:00:00-07:00', location_name: 'Library' },
      after: { starts_at: '2026-12-04T19:00:00-07:00', location_name: 'Library' },
      details_changed: true,
    },
  });
  await page.goto('/notifications');
  await expect(page.getByText('Moved to Fri, Dec 4, 7:30 PM (was 7:00 PM)')).toBeVisible();
  await expect(page.getByText('Details for attendees changed')).toBeVisible();
});
