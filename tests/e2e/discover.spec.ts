// Home's feed (ACT-01).
import { formatDay, formatSoon, rexburgDate } from '../../src/lib/time';
import { expect, expectAccessible, test } from './fixtures';

const HOUR = 60 * 60 * 1000;

// Other tests post at the same time, so each activity has a title of its own.
const named = (title: string) => `${title} ${crypto.randomUUID().slice(0, 8)}`;
// Intl's spaces before AM and PM differ between Node and the Worker.
const loosely = (text: string) => new RegExp(text.replace(/\s/g, '\\s'));

test('a member sees each activity under its day, with who is going', async ({
  page,
  poster,
  host,
}) => {
  const title = named('Board game night');
  // Soon, so it's on the first page.
  const startsAt = new Date(Date.now() + HOUR);
  const id = await host.post({ title, category_id: 'games', starts_at: startsAt.toISOString() });
  await host.admin.from('rsvps').insert({ activity_id: id, user_id: poster.id, status: 'going' });
  await host.admin.from('activities').update({ going_count: 2 }).eq('id', id);

  await page.goto('/discover');
  const day = page.getByRole('region', { name: formatDay(rexburgDate(startsAt), new Date()) });
  const card = day.getByRole('listitem').filter({ hasText: title });
  await expect(card.getByRole('link', { name: title })).toHaveAttribute(
    'href',
    `/activities/${id}`
  );
  await expect(card.getByRole('img', { name: 'Games' })).toBeVisible();
  await expect(card.getByText(loosely(formatSoon(startsAt, new Date())))).toBeVisible();
  await expect(card.getByText('R Mountain trailhead')).toBeVisible();
  await expect(card.getByText('2 going')).toBeVisible();
  await expect(card.getByRole('img', { name: 'Hana Host' })).toBeVisible();
  await expect(card.getByRole('img', { name: 'Pat Poster' })).toBeVisible();
  await expect(card.getByText('✓ Going')).toBeVisible();
  // Nothing is wider than the screen.
  expect(
    await page.evaluate(
      () => document.documentElement.scrollWidth - document.documentElement.clientWidth
    )
  ).toBe(0);
  await expectAccessible(page);

  // The whole card opens the activity, not only its title.
  await card.click();
  await expect(page).toHaveURL(`/activities/${id}`);
});

test('cancelled and hidden activities are not in the feed', async ({ page, signInAs, host }) => {
  await signInAs('member');
  const cancelled = named('Cancelled hike');
  const hidden = named('Hidden hike');
  const soon = new Date(Date.now() + HOUR).toISOString();
  const ids = [
    await host.post({ title: cancelled, starts_at: soon }),
    await host.post({ title: hidden, starts_at: soon }),
  ];
  await host.admin
    .from('activities')
    .update({ status: 'cancelled', cancelled_at: new Date().toISOString() })
    .eq('id', ids[0]);
  await host.admin
    .from('activities')
    .update({ hidden_at: new Date().toISOString() })
    .eq('id', ids[1]);

  await page.goto('/discover');
  await expect(page.getByRole('heading', { level: 1, name: 'Discover' })).toBeVisible();
  await expect(page.getByText(cancelled)).toHaveCount(0);
  await expect(page.getByText(hidden)).toHaveCount(0);
});
