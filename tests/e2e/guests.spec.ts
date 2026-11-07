// Bringing guests (RSVP-06). The pgTAP tests cover the rules and the counts.
import { expect, expectAccessible, test } from './fixtures';

test('a member going says how many guests they are bringing', async ({ page, signInAs, host }) => {
  await signInAs('member');
  const id = await host.post({ guests_allowed: true, max_guests_per_rsvp: 3 });
  await page.goto(`/activities/${id}`);

  await page.getByRole('button', { name: "I'm in" }).click();
  await page.getByRole('button', { name: '✓ Going' }).click();
  const sheet = page.getByRole('dialog', { name: 'Are you going?' });
  const guests = sheet.getByLabel("Guests you're bringing");
  await guests.fill('2');
  await expectAccessible(page);
  await sheet.getByRole('button', { name: 'Save guests' }).click();
  await expect(page.getByRole('status')).toHaveText("You're going with 2 guests.");
  const count = page.getByRole('button', { name: /2 going \(\+2 guests\)$/ });
  await expect(count).toBeVisible();

  // It's saved.
  await page.reload();
  await expect(count).toBeVisible();
  await page.getByRole('button', { name: '✓ Going' }).click();
  await expect(guests).toHaveValue('2');
});

test('the sheet asks about guests only when the organizer welcomes them', async ({
  page,
  signInAs,
  host,
}) => {
  await signInAs('member');
  const id = await host.post();
  await page.goto(`/activities/${id}`);
  await page.getByRole('button', { name: "I'm in" }).click();
  await page.getByRole('button', { name: '✓ Going' }).click();
  const sheet = page.getByRole('dialog', { name: 'Are you going?' });
  await expect(sheet.getByRole('button', { name: 'Maybe' })).toBeVisible();
  await expect(sheet.getByLabel("Guests you're bringing")).toHaveCount(0);
});

test('an organizer welcomes guests when posting', async ({ page, poster }) => {
  await page.goto('/activities/new');
  await page.getByLabel('What are you doing?').fill('Family picnic');
  await page.getByLabel('Start time').fill('12:00');
  await page.getByRole('button', { name: 'Tomorrow' }).click();
  await page.getByLabel('Where?').fill('Porter Park');
  await page.getByRole('radio', { name: 'Food & Socials' }).check();
  await page.getByText('More options').click();
  await page.getByLabel('Guests welcome').check();
  await page.getByLabel('Most guests each member can bring').selectOption('2');
  await page.getByRole('button', { name: 'Post activity' }).click();
  await expect(page.getByRole('heading', { level: 1 })).toHaveText('Family picnic');

  const { data } = await poster.admin
    .from('activities')
    .select('guests_allowed, max_guests_per_rsvp')
    .eq('organizer_id', poster.id)
    .single();
  expect(data).toEqual({ guests_allowed: true, max_guests_per_rsvp: 2 });
});
