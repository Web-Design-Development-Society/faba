// Capacity and "Full" (RSVP-04). The pgTAP tests cover the rules, and this checks them through the
// app and under load.
import { expect, expectAccessible, test } from './fixtures';

test('an organizer posts with a number of spots', async ({ page, poster }) => {
  await page.goto('/activities/new');
  await page.getByLabel('What are you doing?').fill('Board game night');
  await page.getByLabel('Start time').fill('19:00');
  await page.getByRole('button', { name: 'Tomorrow' }).click();
  await page.getByLabel('Where?').fill('Library');
  await page.getByRole('radio', { name: 'Games' }).check();
  await page.getByText('More options').click();
  await page.getByLabel('Spots').fill('12');
  await expectAccessible(page);
  await page.getByRole('button', { name: 'Post activity' }).click();
  await expect(page.getByRole('heading', { level: 1 })).toHaveText('Board game night');

  const { data } = await poster.admin
    .from('activities')
    .select('capacity')
    .eq('organizer_id', poster.id)
    .single();
  expect(data?.capacity).toBe(12);
});

test('a full activity says Full to members who are not going', async ({ page, signInAs, host }) => {
  await signInAs('member');
  const tag = `w${crypto.randomUUID().slice(0, 8)}`;
  // Its organizer takes the only spot.
  const id = await host.post({ title: `Tiny tea ${tag}`, capacity: 1 });

  await page.goto(`/search?q=${tag}`);
  const card = page.getByRole('article').filter({ hasText: `Tiny tea ${tag}` });
  await expect(card.getByText('Full', { exact: true })).toBeVisible();
  await expect(card.getByRole('button', { name: "I'm in" })).toHaveCount(0);

  await page.goto(`/activities/${id}`);
  // The waitlist takes it from here (RSVP-07, waitlist.spec.ts).
  await expect(page.getByRole('button', { name: 'Join waitlist' })).toBeEnabled();
  await expect(page.getByText('Every spot is taken.')).toBeVisible();
  await expectAccessible(page);
});

test("20 members tapping I'm in at once never overfill an activity", async ({ host, crowd }) => {
  const id = await host.post({ capacity: 5 });
  const members = await crowd(20);

  const results = await Promise.all(
    members.map((member) => member.rpc('rsvp', { activity_id: id, status: 'going' }))
  );
  // The organizer has one of the 5 spots.
  expect(results.filter(({ error }) => !error)).toHaveLength(4);
  expect(results.filter(({ error }) => error?.message === 'ACTIVITY_FULL')).toHaveLength(16);

  const { data: activity } = await host.admin
    .from('activities')
    .select('going_count')
    .eq('id', id)
    .single();
  const { count } = await host.admin
    .from('rsvps')
    .select('*', { count: 'exact', head: true })
    .eq('activity_id', id)
    .eq('status', 'going');
  expect(activity?.going_count).toBe(5);
  expect(count).toBe(5);
});
