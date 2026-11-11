// The waitlist (RSVP-07). The pgTAP tests cover the order, the last hour, guests, a new capacity
// and the counts.
import { expect, expectAccessible, test } from './fixtures';

test("a member joins a full activity's waitlist, and is going when a spot opens", async ({
  page,
  poster,
  host,
  crowd,
}) => {
  const tag = `w${crypto.randomUUID().slice(0, 8)}`;
  // Its organizer and one member take both spots.
  const id = await host.post({ title: `Tiny tea ${tag}`, capacity: 2 });
  const [first] = await crowd(1);
  await first.rpc('rsvp', { activity_id: id, status: 'going' });

  await page.goto(`/activities/${id}`);
  await expect(page.getByText('Every spot is taken.')).toBeVisible();
  await page.getByRole('button', { name: 'Join waitlist' }).click();

  await expect(page).toHaveURL(`/activities/${id}`);
  await expect(page.getByRole('status')).toHaveText("You're on the waitlist.");
  await expect(
    page.getByText("You're #1 on the waitlist. You're in if a spot opens.")
  ).toBeVisible();
  await expect(page.getByRole('button', { name: 'Leave waitlist' })).toBeVisible();
  await expectAccessible(page);

  // Its card says so.
  await page.goto(`/search?q=${tag}`);
  const card = page.getByRole('article').filter({ hasText: `Tiny tea ${tag}` });
  await expect(card.getByText('On waitlist', { exact: true })).toBeVisible();

  // The member going leaves, and the spot is theirs.
  await first.rpc('rsvp', { activity_id: id, status: 'not_going' });
  const { data } = await poster.admin
    .from('rsvps')
    .select('status')
    .eq('activity_id', id)
    .eq('user_id', poster.id)
    .single();
  expect(data?.status).toBe('going');

  await page.goto(`/activities/${id}`);
  await expect(page.getByRole('button', { name: '✓ Going' })).toBeVisible();
  await page.goto('/notifications');
  await expect(page.getByText(/A spot opened\. You're going on/)).toBeVisible();
  await expectAccessible(page);
});

test.describe('without JavaScript', () => {
  test.use({ javaScriptEnabled: false });

  test('a member joins the waitlist, then leaves it', async ({ page, poster, host }) => {
    const id = await host.post({ capacity: 1 });
    await page.goto(`/activities/${id}`);
    await page.getByRole('button', { name: 'Join waitlist' }).click();
    await expect(page.getByText("You're #1 on the waitlist.")).toBeVisible();

    await page.getByRole('button', { name: 'Leave waitlist' }).click();
    await expect(page.getByRole('status')).toHaveText("You're not going.");
    await expect(page.getByRole('button', { name: 'Join waitlist' })).toBeVisible();
    const { data } = await poster.admin
      .from('rsvps')
      .select('status')
      .eq('activity_id', id)
      .eq('user_id', poster.id)
      .single();
    expect(data?.status).toBe('not_going');
  });
});
