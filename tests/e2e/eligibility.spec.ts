// A member whose address is no longer byui.edu (AUTH-05). Sign-in stops at Google, so these tests
// mark the account ineligible as sync_my_identity() would, and the pgTAP tests cover the sync.
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
  await expectAccessible(page);
});
