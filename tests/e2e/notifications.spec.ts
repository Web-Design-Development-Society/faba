// The notification center (NOTIF-01), and removing alerts (NOTIF-21). The pgTAP tests cover marking
// notifications read and removing them.
import type { Locator } from '@playwright/test';
import { expect, expectAccessible, expectSquare, paper, test } from './fixtures';

const minutesAgo = (minutes: number) => new Date(Date.now() - minutes * 60 * 1000).toISOString();

/** The color of the dot before an alert's name, or null when it has none. */
const dot = (name: Locator) =>
  name.evaluate((el) => {
    const before = getComputedStyle(el, '::before');
    return before.content === 'none' ? null : before.borderTopColor;
  });

test('the center has new and earlier alerts, and opening one marks it read', async ({
  page,
  poster,
  host,
}) => {
  const id = await host.post();
  await poster.admin.from('notifications').insert([
    {
      recipient_id: poster.id,
      type: 'activity_changed',
      activity_id: id,
      created_at: minutesAgo(5),
    },
    { recipient_id: poster.id, type: 'reminder', activity_id: id, created_at: minutesAgo(1) },
    // Its activity is gone.
    {
      recipient_id: poster.id,
      type: 'activity_cancelled',
      created_at: minutesAgo(60),
      read_at: minutesAgo(30),
    },
  ]);

  await page.goto('/notifications');
  const fresh = page.getByRole('region', { name: 'New' });
  const earlier = page.getByRole('region', { name: 'Earlier' });
  await expect(fresh.getByRole('listitem')).toHaveText([
    /Unread: Reminder\s*Sunrise hike up the R/,
    /Unread: Time or place changed\s*Sunrise hike up the R/,
  ]);
  await expect(earlier.getByRole('listitem')).toHaveText([/Cancelled\s*No longer available/]);
  await expectAccessible(page);

  await fresh.getByRole('button', { name: /^Unread: Time or place changed/ }).click();
  await expect(page).toHaveURL(`/activities/${id}`);
  await page.goto('/notifications');
  await expect(fresh.getByRole('listitem')).toHaveCount(1);

  await page.getByRole('button', { name: 'Mark all read' }).click();
  await expect(page.getByRole('status')).toHaveText('All caught up.');
  await expect(fresh).toHaveCount(0);
  await expect(earlier.getByRole('listitem')).toHaveCount(3);
});

test('with no alerts, the center says so', async ({ page, poster }) => {
  expect(poster.id).toBeTruthy();
  await page.goto('/notifications');
  await expect(
    page.getByText("You're all caught up. We'll let you know when plans change.")
  ).toBeVisible();
  await expect(page.getByRole('button', { name: 'Mark all read' })).toHaveCount(0);
});

test('each alert is a card, and Unread shows only the new ones', async ({ page, poster, host }) => {
  const id = await host.post();
  await poster.admin.from('notifications').insert([
    {
      recipient_id: poster.id,
      type: 'reminder',
      activity_id: id,
      created_at: minutesAgo(1),
      payload: { starts_at: new Date(Date.now() + 60 * 60 * 1000).toISOString() },
    },
    {
      recipient_id: poster.id,
      type: 'rsvp_confirmed',
      activity_id: id,
      // Rows inserted together need the same columns, or a missing one is null.
      payload: {},
      created_at: minutesAgo(30),
      read_at: minutesAgo(20),
    },
  ]);

  await page.goto('/notifications');
  const show = page.getByRole('navigation', { name: 'Show' });
  await expect(show.getByRole('link', { name: 'All' })).toHaveAttribute('aria-current', 'page');

  // Each is paper with square corners and a shadow (UI-15, UI-16): the new one light blue with a
  // dot before its name, and the earlier one white with none. It has three lines and nothing else
  // (UI-20): the name in the display face, then what happened, then how long ago.
  const card = page.getByRole('region', { name: 'New' }).locator('.alert');
  const read = page.getByRole('region', { name: 'Earlier' }).locator('.alert');
  const title = card.getByText('Sunrise hike up the R');
  expect(await paper(card)).toBe('cfe1fa');
  expect(await dot(title)).toBe('rgb(0, 108, 194)');
  expect(await paper(read)).toBe('ffffff');
  await expectSquare(card);
  expect(await dot(read.getByText('Sunrise hike up the R'))).toBeNull();
  await expect(title).toHaveCSS('font-family', /^Anton/);
  await expect(title).toHaveCSS('text-transform', 'capitalize');
  const [name, sentence] = [
    (await title.boundingBox())!,
    (await card.getByText(/Reminder: /).boundingBox())!,
  ];
  const ago = (await card.getByText(/^(just now|\d+[mhd] ago)$/).boundingBox())!;
  expect(name.y).toBeLessThan(sentence.y);
  expect(sentence.y).toBeLessThan(ago.y);
  await expect(card.locator('svg, .tile, .chevron')).toHaveCount(0);
  // With no border to color, hovering underlines the name.
  await card.hover();
  await expect(title).toHaveCSS('text-decoration-line', 'underline');
  expect(await page.evaluate(() => document.documentElement.scrollWidth <= window.innerWidth)).toBe(
    true
  );
  await expectAccessible(page);

  await show.getByRole('link', { name: 'Unread' }).click();
  await expect(page).toHaveURL('/notifications?show=unread');
  await expect(show.getByRole('link', { name: 'Unread' })).toHaveAttribute('aria-current', 'page');
  await expect(page.getByRole('region', { name: 'New' }).getByRole('listitem')).toHaveCount(1);
  await expect(page.getByRole('region', { name: 'Earlier' })).toHaveCount(0);

  await page.getByRole('button', { name: 'Mark all read' }).click();
  await page.goto('/notifications?show=unread');
  await expect(page.getByText("You're all caught up.", { exact: true })).toBeVisible();
});

test('a member removes alerts one at a time, or clears the read ones', async ({
  page,
  poster,
  host,
}) => {
  const id = await host.post();
  // Three new alerts and two read ones, all about the same activity.
  const alert = (type: string, minutes: number, read: boolean) => ({
    recipient_id: poster.id,
    type,
    activity_id: id,
    payload: type === 'new_attendees' ? { count: 2 } : {},
    created_at: minutesAgo(minutes),
    read_at: read ? minutesAgo(1) : null,
  });
  await poster.admin
    .from('notifications')
    .insert([
      alert('reminder', 1, false),
      alert('activity_changed', 2, false),
      alert('activity_cancelled', 3, false),
      alert('rsvp_confirmed', 30, true),
      alert('new_attendees', 40, true),
    ]);

  await page.goto('/notifications');
  const badge = page
    .getByRole('navigation', { name: 'Main' })
    .getByRole('link', { name: /^Alerts/ });
  const fresh = page.getByRole('region', { name: 'New' });
  const earlier = page.getByRole('region', { name: 'Earlier' });
  await expect(badge).toHaveAccessibleName('Alerts 3 unread');

  // Each has a Remove button at its top right, 44 px square, named for what happened and the
  // activity, as its card is read. It's the muted color.
  const changed = fresh.getByRole('listitem').nth(1);
  const remove = changed.getByRole('button', {
    name: /^Remove alert: Time or place changed, Sunrise hike up the R/,
  });
  await expect(remove).toHaveCSS('color', 'rgb(75, 85, 99)');
  const [x, card] = [(await remove.boundingBox())!, (await changed.boundingBox())!];
  expect(x.width).toBeGreaterThanOrEqual(44);
  expect(x.height).toBeGreaterThanOrEqual(44);
  expect(Math.abs(x.x + x.width - (card.x + card.width))).toBeLessThan(1);
  expect(Math.abs(x.y - card.y)).toBeLessThan(1);
  await expectAccessible(page);

  // Removing it takes it off the list, marks it read, and comes back at the one after it.
  const cancelled = await fresh.getByRole('listitem').nth(2).getAttribute('id');
  await remove.click();
  await expect(page.getByRole('status')).toHaveText('Alert removed.');
  await expect(page).toHaveURL(`/notifications#${cancelled}`);
  await expect(fresh.getByRole('listitem')).toHaveText([/Reminder/, /Cancelled/]);
  await expect(badge).toHaveAccessibleName('Alerts 2 unread');

  // On Unread, it stays on Unread, and the last one comes back at the one before it.
  await page.goto('/notifications?show=unread');
  const reminder = await fresh.getByRole('listitem').first().getAttribute('id');
  await fresh.getByRole('button', { name: /^Remove alert: Cancelled, / }).click();
  await expect(page).toHaveURL(`/notifications?show=unread#${reminder}`);
  await expect(fresh.getByRole('listitem')).toHaveText([/Reminder/]);

  // Earlier's Clear removes the read ones, and the new reminder stays.
  await page.goto('/notifications');
  await expect(earlier.getByRole('listitem')).toHaveCount(2);
  await expect(fresh.getByRole('button', { name: /^Clear/ })).toHaveCount(0);
  const clear = earlier.getByRole('button', { name: 'Clear earlier alerts' });
  // It says Clear, and screen readers hear the rest.
  await expect(clear.locator('.visually-hidden')).toHaveText('earlier alerts');
  await expect(clear).toHaveCSS('color', 'rgb(180, 35, 24)');
  await expectAccessible(page);
  await clear.click();
  await expect(page.getByRole('status')).toHaveText('Earlier alerts cleared.');
  await expect(earlier).toHaveCount(0);
  await expect(fresh.getByRole('listitem')).toHaveText([/Reminder/]);
  await expect(badge).toHaveAccessibleName('Alerts 1 unread');

  // Removing the last one leaves nothing to come back to.
  await fresh.getByRole('button', { name: /^Remove alert: Reminder/ }).click();
  await expect(page).toHaveURL('/notifications');
  await expect(
    page.getByText("You're all caught up. We'll let you know when plans change.")
  ).toBeVisible();
  await expect(badge).not.toHaveAccessibleName(/unread/);
});
