// Saying I'm in (RSVP-01), and changing it (RSVP-02).
import type { SupabaseClient } from '@supabase/supabase-js';
import { expect, expectAccessible, test } from './fixtures';

const HOUR = 60 * 60 * 1000;

// Other tests post at the same time, so each activity has a title of its own.
const named = (title: string) => `${title} ${crypto.randomUUID().slice(0, 8)}`;

/** A member's RSVP to an activity, or null without one. */
async function statusOf(admin: SupabaseClient, activityId: string, userId: string) {
  const { data } = await admin
    .from('rsvps')
    .select('status')
    .eq('activity_id', activityId)
    .eq('user_id', userId)
    .maybeSingle();
  return data?.status ?? null;
}

test("I'm in shows at once, and Undo takes it back", async ({ page, poster, host }) => {
  const id = await host.post();
  await page.goto(`/activities/${id}`);
  await page.getByRole('button', { name: "I'm in" }).click();

  await expect(page.getByRole('button', { name: '✓ Going' })).toBeFocused();
  await expect(page.getByText('2 going')).toBeVisible();
  await expect(page.getByRole('img', { name: 'Pat Poster' })).toBeVisible();
  const status = page.getByRole('status');
  await expect(status).toContainText("You're going.");
  await expect(page).toHaveURL(`/activities/${id}`);
  await expect.poll(() => statusOf(host.admin, id, poster.id)).toBe('going');
  await expectAccessible(page);

  await status.getByRole('button', { name: 'Undo' }).click();
  await expect(page.getByRole('button', { name: "I'm in" })).toBeFocused();
  await expect(page.getByText('1 going')).toBeVisible();
  await expect(page.getByRole('img', { name: 'Pat Poster' })).toHaveCount(0);
  await expect(status).toHaveText('Undone.');
  await expect.poll(() => statusOf(host.admin, id, poster.id)).toBe('not_going');
});

test("I'm in on a card stays on Discover, and the toast goes after 5 seconds", async ({
  page,
  poster,
  host,
}) => {
  await page.clock.install();
  const title = named('Board game night');
  const id = await host.post({ title, starts_at: new Date(Date.now() + HOUR).toISOString() });
  await page.goto('/discover');
  const card = page.getByRole('listitem').filter({ hasText: title });
  await card.getByRole('button', { name: "I'm in" }).click();

  await expect(card.getByRole('button', { name: '✓ Going' })).toBeVisible();
  await expect(card.getByText('2 going')).toBeVisible();
  await expect(card.getByRole('img', { name: 'Pat Poster' })).toBeVisible();
  await expect(page).toHaveURL('/discover');
  await expect.poll(() => statusOf(host.admin, id, poster.id)).toBe('going');

  const status = page.getByRole('status');
  await expect(status).toContainText("You're going.");
  // A toast under the pointer would stay.
  await page.mouse.move(0, 0);
  await page.clock.runFor(5000);
  await expect(status).toBeEmpty();
});

test("if I'm in can't be saved, it goes back and says why", async ({ page, poster, host }) => {
  const id = await host.post();
  await page.goto(`/activities/${id}`);
  await host.admin
    .from('activities')
    .update({ status: 'cancelled', cancelled_at: new Date().toISOString() })
    .eq('id', id);
  await page.getByRole('button', { name: "I'm in" }).click();

  await expect(page.getByRole('status')).toHaveText(
    "This activity is cancelled, so it isn't taking RSVPs."
  );
  await expect(page.getByRole('button', { name: "I'm in" })).toBeVisible();
  await expect(page.getByText('1 going')).toBeVisible();
  await expect(page.getByRole('img', { name: 'Pat Poster' })).toHaveCount(0);
  expect(await statusOf(host.admin, id, poster.id)).toBeNull();
});

test("✓ Going opens a sheet, and Can't make it takes the member off the list", async ({
  page,
  poster,
  host,
}) => {
  const id = await host.post();
  await page.goto(`/activities/${id}`);
  await page.getByRole('button', { name: "I'm in" }).click();
  await expect.poll(() => statusOf(host.admin, id, poster.id)).toBe('going');

  await page.getByRole('button', { name: '✓ Going' }).click();
  const sheet = page.getByRole('dialog', { name: 'Are you going?' });
  await expect(sheet.getByRole('button', { name: 'Going', exact: true })).toBeFocused();
  await expect(sheet.getByRole('button', { name: 'Going', exact: true })).toHaveAttribute(
    'aria-pressed',
    'true'
  );
  await expectAccessible(page);

  await sheet.getByRole('button', { name: "Can't make it" }).click();
  await expect(sheet).toBeHidden();
  await expect(page.getByRole('button', { name: "I'm in" })).toBeFocused();
  await expect(page.getByText('1 going')).toBeVisible();
  await expect(page.getByRole('img', { name: 'Pat Poster' })).toHaveCount(0);
  await expect(page.getByRole('status')).toHaveText("You're not going.");
  await expect.poll(() => statusOf(host.admin, id, poster.id)).toBe('not_going');
});

test("on a card, Going keeps the RSVP, and Can't make it changes the next plan too", async ({
  page,
  poster,
  host,
}) => {
  const title = named('Board game night');
  const id = await host.post({ title, starts_at: new Date(Date.now() + HOUR).toISOString() });
  await page.goto('/discover');
  const card = page.getByRole('listitem').filter({ hasText: title });
  await card.getByRole('button', { name: "I'm in" }).click();
  await expect.poll(() => statusOf(host.admin, id, poster.id)).toBe('going');

  // Now the page comes from the server with ✓ Going.
  await page.reload();
  const going = card.getByRole('button', { name: '✓ Going' });
  await going.click();
  // The choices are readable on the white sheet, not white like other buttons, and the member's
  // answer stands out.
  const sheet = page.getByRole('dialog', { name: 'Are you going?' });
  for (const name of ['Going', 'Maybe', "Can't make it"]) {
    await expect(sheet.getByRole('button', { name, exact: true })).not.toHaveCSS(
      'color',
      'rgb(255, 255, 255)'
    );
  }
  await expect(sheet.getByRole('button', { name: 'Going', exact: true })).toHaveCSS(
    'font-weight',
    '600'
  );
  await expect(sheet.getByRole('button', { name: 'Maybe', exact: true })).toHaveCSS(
    'font-weight',
    '400'
  );
  await page.getByRole('button', { name: 'Going', exact: true }).click();
  await expect(page.getByRole('dialog')).toBeHidden();
  await expect(going).toBeFocused();

  await page.keyboard.press('Enter');
  await page.getByRole('button', { name: "Can't make it" }).click();
  await expect(card.getByRole('button', { name: "I'm in" })).toBeVisible();
  await expect(card.getByText('1 going')).toBeVisible();
  // Even the face that came from the server goes.
  await expect(card.getByRole('img', { name: 'Pat Poster' })).toHaveCount(0);
  const plan = page.getByRole('region', { name: 'Your next plan' });
  await expect(plan.getByRole('button', { name: "I'm in" })).toBeVisible();
  await expect.poll(() => statusOf(host.admin, id, poster.id)).toBe('not_going');
});

test.describe('without JavaScript', () => {
  test.use({ javaScriptEnabled: false });

  test("I'm in on an activity's page saves the RSVP and comes back", async ({
    page,
    poster,
    host,
  }) => {
    const id = await host.post();
    await page.goto(`/activities/${id}`);
    await page.getByRole('button', { name: "I'm in" }).click();

    await expect(page).toHaveURL(`/activities/${id}`);
    await expect(page.getByRole('status')).toHaveText("You're going.");
    await expect(page.getByText('✓ Going')).toBeVisible();
    await expect(page.getByText('2 going')).toBeVisible();
    await expect(page.getByRole('img', { name: 'Pat Poster' })).toBeVisible();
    expect(await statusOf(host.admin, id, poster.id)).toBe('going');

    // Reloading doesn't post again, and the message has gone.
    await page.reload();
    await expect(page.getByText('2 going')).toBeVisible();
    await expect(page.getByRole('status')).toHaveText('');
  });

  test("I'm in on a card comes back to the card", async ({ page, poster, host }) => {
    const title = named('Board game night');
    // Soon, so it's on the first page.
    const id = await host.post({ title, starts_at: new Date(Date.now() + HOUR).toISOString() });
    await page.goto('/discover');
    const card = page.getByRole('listitem').filter({ hasText: title });
    await card.getByRole('button', { name: "I'm in" }).click();

    await expect(page).toHaveURL(`/discover#activity-${id}`);
    await expect(card.getByText('✓ Going')).toBeVisible();
    await expect(card.getByText('2 going')).toBeVisible();
    await expect(card.getByRole('img', { name: 'Pat Poster' })).toBeVisible();
    await expect(page.getByRole('region', { name: 'Your next plan' })).toContainText(title);
    expect(await statusOf(host.admin, id, poster.id)).toBe('going');
  });

  test("✓ Going opens a sheet, and Can't make it saves and comes back", async ({
    page,
    poster,
    host,
  }) => {
    const id = await host.post();
    await page.goto(`/activities/${id}`);
    await page.getByRole('button', { name: "I'm in" }).click();
    await page.getByRole('button', { name: '✓ Going' }).click();
    await page.getByRole('dialog').getByRole('button', { name: "Can't make it" }).click();

    await expect(page).toHaveURL(`/activities/${id}`);
    await expect(page.getByRole('status')).toHaveText("You're not going.");
    await expect(page.getByRole('button', { name: "I'm in" })).toBeVisible();
    await expect(page.getByText('1 going')).toBeVisible();
    await expect(page.getByRole('img', { name: 'Pat Poster' })).toHaveCount(0);
    expect(await statusOf(host.admin, id, poster.id)).toBe('not_going');
  });

  test("I'm in says why when the activity was cancelled meanwhile", async ({
    page,
    poster,
    host,
  }) => {
    const id = await host.post();
    await page.goto(`/activities/${id}`);
    await host.admin
      .from('activities')
      .update({ status: 'cancelled', cancelled_at: new Date().toISOString() })
      .eq('id', id);
    await page.getByRole('button', { name: "I'm in" }).click();

    await expect(page.getByRole('alert')).toHaveText(
      "This activity is cancelled, so it isn't taking RSVPs."
    );
    await expect(page.getByText('1 going')).toBeVisible();
    await expect(page.getByRole('button', { name: "I'm in" })).toBeDisabled();
    expect(await statusOf(host.admin, id, poster.id)).toBeNull();
  });
});

test("an activity that's over has no I'm in", async ({ page, signInAs, host }) => {
  await signInAs('member');
  const title = named('Lunch walk');
  const id = await host.post({ title });
  await host.admin
    .from('activities')
    .update({
      starts_at: new Date(Date.now() - 2 * HOUR).toISOString(),
      ends_at: new Date(Date.now() - HOUR).toISOString(),
    })
    .eq('id', id);

  await page.goto(`/activities/${id}`);
  await expect(page.getByText('This activity is over.')).toBeVisible();
  await expect(page.getByRole('button', { name: "I'm in" })).toBeDisabled();

  // The feed still shows it for 3 hours after it starts.
  await page.goto('/discover');
  const card = page.getByRole('listitem').filter({ hasText: title });
  await expect(card).toBeVisible();
  await expect(card.getByRole('button', { name: "I'm in" })).toHaveCount(0);
  // With JavaScript, because axe runs in the page. The other cards have I'm in.
  await expectAccessible(page);
});
