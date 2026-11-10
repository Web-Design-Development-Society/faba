// A member whose address is no longer byui.edu (AUTH-05), and moderators handing over their
// activities. Sign-in stops at Google, so these tests mark the account ineligible as
// sync_my_identity() would, and the pgTAP tests cover the sync.
import { expect, expectAccessible, test } from './fixtures';

test('an ineligible member is signed out and sees Not eligible', async ({ page, poster }) => {
  await poster.admin.from('profiles').update({ status: 'ineligible' }).eq('id', poster.id);
  await page.goto('/discover');
  await expect(page).toHaveURL('/not-eligible');
  await expect(page.getByRole('heading', { level: 1 })).toHaveText('FABA is for BYU-Idaho faculty');
  await expectAccessible(page);

  await page.goto('/me');
  await expect(page).toHaveURL(/\/auth\/login/);
});

test("an ineligible organizer's activity stays up, with a note", async ({
  page,
  signInAs,
  host,
}) => {
  await signInAs('member');
  const id = await host.post();
  await host.admin.from('profiles').update({ status: 'ineligible' }).eq('id', host.id);

  await page.goto(`/activities/${id}`);
  await expect(page.getByRole('heading', { level: 1 })).toHaveText('Sunrise hike up the R');
  await expect(page.getByText('Organizer no longer active')).toBeVisible();
  await expect(page.getByText('Hosted by')).toHaveCount(0);
  await expect(page.getByRole('button', { name: 'Cancel it' })).toHaveCount(0);
  await expectAccessible(page);
});

test("a moderator gives an ineligible organizer's activity to someone going", async ({
  page,
  signInAs,
  host,
}) => {
  await signInAs('moderator');
  const title = `Board game night ${crypto.randomUUID().slice(0, 8)}`;
  const id = await host.post({ title });
  await host.admin.from('profiles').update({ status: 'ineligible' }).eq('id', host.id);
  try {
    await page.goto('/mod');
    await page
      .getByRole('region', { name: 'Organizer no longer active' })
      .getByRole('link', { name: title })
      .click();
    await expect(page.getByText('Organizer no longer active · Hana Host')).toBeVisible();
    // Only someone going can host it, so the moderator goes first.
    await expect(page.getByRole('button', { name: 'Give to a new host' })).toHaveCount(0);
    // ✓ Going shows before the RSVP is saved, so the reload waits for it.
    const saved = page.waitForResponse((response) =>
      response.url().includes('/_actions/rsvps.set')
    );
    await page.getByRole('button', { name: "I'm in" }).click();
    await expect(page.getByRole('button', { name: '✓ Going' })).toBeVisible();
    expect((await saved).ok()).toBe(true);
    await page.reload();

    await page.getByRole('button', { name: 'Give to a new host' }).click();
    const sheet = page.getByRole('dialog', { name: 'Give this activity to a new host?' });
    await sheet.getByLabel('New host').selectOption({ index: 0 });
    await sheet.getByLabel('Reason, for the audit log').fill('I agreed to host it');
    await expectAccessible(page);
    await sheet.getByRole('button', { name: 'Yes, give it to them' }).click();
    await expect(page.getByRole('status')).toHaveText('New host set.');
    await expect(page.getByText("You're hosting")).toBeVisible();

    const { data: activity } = await host.admin
      .from('activities')
      .select('organizer_id')
      .eq('id', id)
      .single();
    expect(activity?.organizer_id).not.toBe(host.id);
  } finally {
    // It's the moderator's now, so deleting Hana's account wouldn't delete it.
    await host.admin.from('activities').delete().eq('id', id);
  }
});

test("a moderator cancels an ineligible organizer's activity", async ({ page, signInAs, host }) => {
  await signInAs('moderator');
  const id = await host.post();
  await host.admin.from('profiles').update({ status: 'ineligible' }).eq('id', host.id);

  await page.goto(`/activities/${id}`);
  await page.getByRole('button', { name: 'Cancel it' }).click();
  const sheet = page.getByRole('dialog', { name: 'Cancel this activity?' });
  await expect(sheet).toContainText('its organizer is no longer active');
  await sheet.getByLabel('Reason, for the audit log').fill('Nobody can host it');
  await sheet.getByRole('button', { name: 'Yes, cancel it' }).click();
  await expect(page.getByRole('status')).toHaveText('Cancelled.');
  await expect(page.getByText('Cancelled: Its organizer is no longer active.')).toBeVisible();
  await expect(page.getByRole('button', { name: 'Cancel it' })).toHaveCount(0);
  await expectAccessible(page);
});
