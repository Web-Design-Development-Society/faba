// Post again (ACT-07). The pgTAP tests cover which copied_from_id is kept.
import { expect, expectAccessible, test } from './fixtures';

test('the organizer posts a past activity again, with a new date', async ({ page, poster }) => {
  const lastWeek = new Date(Date.now() - 7 * 24 * 60 * 60 * 1000);
  const { data: original } = await poster.admin
    .from('activities')
    .insert({
      organizer_id: poster.id,
      category_id: 'games',
      title: 'Board game night',
      description: 'Bring a game.',
      starts_at: lastWeek.toISOString(),
      ends_at: new Date(lastWeek.getTime() + 2 * 60 * 60 * 1000).toISOString(),
      location_name: 'Library',
      cost_note: 'Free',
      capacity: 12,
    })
    .select('id')
    .single();
  await poster.admin
    .from('rsvps')
    .insert({ activity_id: original!.id, user_id: poster.id, status: 'going' });
  await poster.admin
    .from('activity_private_details')
    .insert({ activity_id: original!.id, details: 'Room 204' });
  await poster.admin.from('activity_tags').insert({ activity_id: original!.id, tag_id: 'free' });

  await page.goto(`/activities/${original!.id}`);
  await page.getByRole('link', { name: 'Post again' }).click();
  await expect(page).toHaveURL(`/activities/new?from=${original!.id}`);
  await expect(
    page.getByText('Copied from Board game night. Pick a new date and time.')
  ).toBeVisible();
  await expect(page.getByLabel('What are you doing?')).toHaveValue('Board game night');
  await expect(page.getByLabel('Where?')).toHaveValue('Library');
  await expect(page.getByRole('radio', { name: 'Games' })).toBeChecked();
  await expect(page.getByLabel('Details (optional)')).toHaveValue('Bring a game.');
  await expect(page.getByLabel('Cost')).toHaveValue('Free');
  await expect(page.getByLabel('Spots')).toHaveValue('12');
  await expect(page.getByLabel('Details for attendees only')).toHaveValue('Room 204');
  await expect(page.getByRole('checkbox', { name: 'Free' })).toBeChecked();
  // Everything but the date and times, which start from the suggestion.
  await expect(page.getByLabel('End time')).toHaveValue('');
  await expect(page.getByLabel('Date')).not.toHaveValue('');
  await expectAccessible(page);

  await page.getByRole('button', { name: 'Post activity' }).click();
  await expect(page.getByRole('status')).toHaveText('Posted!');
  const id = page.url().split('/').pop()!;
  expect(id).not.toBe(original!.id);
  const { data: copy } = await poster.admin
    .from('activities')
    .select('title, copied_from_id, starts_at')
    .eq('id', id)
    .single();
  expect(copy).toEqual(
    expect.objectContaining({ title: 'Board game night', copied_from_id: original!.id })
  );
  expect(new Date(copy!.starts_at).getTime()).toBeGreaterThan(Date.now());
});

test('Post again shows only once it is over or cancelled', async ({ page, poster }) => {
  const { data: upcoming } = await poster.admin
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
  await page.goto(`/activities/${upcoming!.id}`);
  await expect(page.getByRole('link', { name: 'Edit', exact: true })).toBeVisible();
  await expect(page.getByRole('link', { name: 'Post again' })).toHaveCount(0);

  await poster.admin
    .from('activities')
    .update({ status: 'cancelled', cancelled_at: new Date().toISOString() })
    .eq('id', upcoming!.id);
  await page.reload();
  await expect(page.getByRole('link', { name: 'Post again' })).toBeVisible();
});

test("someone else's activity can't be copied", async ({ page, poster, host }) => {
  expect(poster.id).toBeTruthy();
  const id = await host.post({ title: 'Chess club' });
  await page.goto(`/activities/new?from=${id}`);
  await expect(page.getByText(/Copied from/)).toHaveCount(0);
  await expect(page.getByLabel('What are you doing?')).toHaveValue('');
});
