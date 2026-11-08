// Plans (RSVP-08), which replaced My activities on the Me screen (HIST-02).
import type { SupabaseClient } from '@supabase/supabase-js';
import { expect, expectAccessible, test } from './fixtures';

const HOUR = 60 * 60 * 1000;

// Other tests post at the same time, so each activity has a title of its own.
const named = (title: string) => `${title} ${crypto.randomUUID().slice(0, 8)}`;
const inHours = (hours: number) => new Date(Date.now() + hours * HOUR).toISOString();

/** Makes `member` going to activity `id`, and counts them, as rsvp() would. */
async function goTo(admin: SupabaseClient, id: string, member: string) {
  await admin.from('rsvps').insert({ activity_id: id, user_id: member, status: 'going' });
  const { data } = await admin.from('activities').select('going_count').eq('id', id).single();
  await admin
    .from('activities')
    .update({ going_count: data!.going_count + 1 })
    .eq('id', id);
}

test('Plans has what the member is going to, organizing and went to, with badges', async ({
  page,
  poster,
  host,
}) => {
  const cancelled = named('Sledding');
  const organized = named('Pickleball');
  const going = named('Board game night');
  const later = named('Not going');

  const cancelledId = await host.post({ title: cancelled, starts_at: inHours(24) });
  await goTo(host.admin, cancelledId, poster.id);
  await host.admin
    .from('activities')
    .update({
      status: 'cancelled',
      cancel_reason: 'No snow',
      cancelled_at: new Date().toISOString(),
    })
    .eq('id', cancelledId);

  // Pat posts one, and is going, as create_activity() makes them.
  const { data: mine } = await poster.admin
    .from('activities')
    .insert({
      organizer_id: poster.id,
      category_id: 'sports',
      title: organized,
      starts_at: inHours(36),
      location_name: 'Hart courts',
      going_count: 0,
    })
    .select('id')
    .single();
  await goTo(poster.admin, mine!.id, poster.id);

  // Its place changed, and Pat has the last spot.
  const goingId = await host.post({ title: going, category_id: 'games', starts_at: inHours(48) });
  await goTo(host.admin, goingId, poster.id);
  await host.admin
    .from('activities')
    .update({ capacity: 2, time_or_place_changed_at: new Date().toISOString() })
    .eq('id', goingId);
  await host.post({ title: later, starts_at: inHours(30) });

  // Over, so it's in Past.
  const yesterday = named('Yesterday');
  const { data: past } = await host.admin
    .from('activities')
    .insert({
      organizer_id: host.id,
      category_id: 'outdoors',
      title: yesterday,
      starts_at: inHours(-5),
      location_name: 'R Mountain trailhead',
    })
    .select('id')
    .single();
  await goTo(host.admin, past!.id, poster.id);

  // Going has what Pat is going to but doesn't organize, soonest first.
  await page.goto('/me');
  await page.getByRole('navigation', { name: 'Main' }).getByRole('link', { name: 'Plans' }).click();
  await expect(
    page.getByRole('navigation', { name: 'Main' }).getByRole('link', { name: 'Plans' })
  ).toHaveAttribute('aria-current', 'page');
  const segments = page.getByRole('navigation', { name: 'Plans' });
  await expect(segments.getByRole('link', { name: 'Going' })).toHaveAttribute(
    'aria-current',
    'page'
  );
  const titles = page.getByRole('main').getByRole('heading', { level: 3 });
  await expect(titles).toHaveText([cancelled, going]);
  const card = (title: string) => page.getByRole('listitem').filter({ hasText: title });
  await expect(card(cancelled).getByText('Cancelled', { exact: true })).toBeVisible();
  await expect(card(cancelled).getByRole('button')).toHaveCount(0);
  await expect(card(going).getByRole('button', { name: '✓ Going' })).toBeVisible();
  await expect(card(going).getByRole('listitem')).toHaveText(['Changed', 'Full']);
  await expectAccessible(page);

  await segments.getByRole('link', { name: 'Organizing' }).click();
  await expect(page).toHaveURL('/plans?show=organizing');
  await expect(titles).toHaveText([organized]);
  await expect(card(organized).getByText("You're hosting")).toBeVisible();

  await segments.getByRole('link', { name: 'Past' }).click();
  await expect(titles).toHaveText([yesterday]);

  await segments.getByRole('link', { name: 'Going' }).click();

  // Each opens the activity.
  await card(cancelled).click();
  await expect(page).toHaveURL(`/activities/${cancelledId}`);
  await expect(page.getByText('Cancelled: No snow')).toBeVisible();
});

test('with no plans, Plans invites the member to browse', async ({ page, poster }) => {
  const { count } = await poster.admin
    .from('rsvps')
    .select('*', { count: 'exact', head: true })
    .eq('user_id', poster.id);
  expect(count).toBe(0);

  await page.goto('/plans');
  await expect(page.getByText('No plans yet. Find something fun.')).toBeVisible();
  await expect(page.getByRole('link', { name: 'Browse activities' })).toHaveAttribute(
    'href',
    '/discover'
  );
});

test.describe('without JavaScript', () => {
  test.use({ javaScriptEnabled: false });

  test("Can't make it comes back to Plans, without the activity", async ({
    page,
    poster,
    host,
  }) => {
    const title = named('Board game night');
    const id = await host.post({ title, starts_at: inHours(24) });
    await goTo(host.admin, id, poster.id);

    await page.goto('/plans');
    const card = page.getByRole('listitem').filter({ hasText: title });
    await card.getByRole('button', { name: '✓ Going' }).click();
    await page.getByRole('dialog').getByRole('button', { name: "Can't make it" }).click();

    await expect(page).toHaveURL(`/plans#activity-${id}`);
    await expect(page.getByRole('status')).toHaveText("You're not going.");
    await expect(page.getByText(title)).toHaveCount(0);
  });
});
