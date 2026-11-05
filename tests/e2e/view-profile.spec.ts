// A member's profile (PROF-03).
import { expect, expectAccessible, test } from './fixtures';

const HOUR = 60 * 60 * 1000;
const inHours = (hours: number) => new Date(Date.now() + hours * HOUR).toISOString();

// Personas: Oscar Organizer, who shares his email, and Sam Suspended.
const OSCAR = '00000000-0000-4000-8000-000000000002';
const SAM = '00000000-0000-4000-8000-000000000005';

test("the organizer's name opens their profile, with what they're organizing", async ({
  page,
  signInAs,
  host,
}) => {
  await signInAs('member');
  await host.admin
    .from('profiles')
    .update({ department: 'Biology', bio: 'I lead hikes.', interests: ['outdoors', 'food'] })
    .eq('id', host.id);
  await host.admin
    .from('profile_private')
    .update({ faculty_type: 'part_time' })
    .eq('user_id', host.id);
  const id = await host.post();
  // Cancelled, hidden and past activities aren't coming up.
  const cancelled = await host.post({ title: 'Sledding' });
  await host.admin
    .from('activities')
    .update({ status: 'cancelled', cancelled_at: new Date().toISOString() })
    .eq('id', cancelled);
  const hidden = await host.post({ title: 'Ticket sale' });
  await host.admin
    .from('activities')
    .update({ hidden_at: new Date().toISOString() })
    .eq('id', hidden);
  const past = await host.post({ title: 'Breakfast' });
  await host.admin
    .from('activities')
    .update({ starts_at: inHours(-5), ends_at: inHours(-4) })
    .eq('id', past);

  await page.goto(`/activities/${id}`);
  await page.getByRole('link', { name: 'Hana Host' }).click();
  await expect(page).toHaveURL(`/people/${host.id}`);
  await expect(page.getByRole('heading', { level: 1 })).toHaveText('Hana Host');
  await expect(page.getByText('Biology')).toBeVisible();
  await expect(page.getByText('I lead hikes.')).toBeVisible();
  await expect(page.getByText('Interests: Outdoors, Food')).toBeVisible();
  const organizing = page.getByRole('region', { name: 'Organizing' });
  await expect(organizing.getByRole('article')).toHaveCount(1);
  await expect(organizing.getByRole('link', { name: 'Sunrise hike up the R' })).toHaveAttribute(
    'href',
    `/activities/${id}`
  );
  // She doesn't share her email, and her faculty type is never shown.
  await expect(page.getByText('Email:')).toHaveCount(0);
  await expect(page.locator('main')).not.toContainText(/part-time/i);
  await expectAccessible(page);

  await page.getByLabel('More actions').click();
  await expect(page.getByRole('link', { name: 'Report' })).toHaveAttribute(
    'href',
    `/people/${host.id}/report`
  );
});

test('a member who shares their email has it on their profile', async ({ page, signInAs }) => {
  await signInAs('member');
  await page.goto(`/people/${OSCAR}`);
  await expect(page.getByRole('heading', { level: 1 })).toHaveText('Oscar Organizer');
  await expect(page.getByRole('link', { name: 'organizer.test@byui.edu' })).toHaveAttribute(
    'href',
    'mailto:organizer.test@byui.edu'
  );
});

test("a member who isn't active shows only that", async ({ page, signInAs, host }) => {
  await signInAs('member');
  await host.admin.from('profiles').update({ status: 'ineligible' }).eq('id', host.id);

  // Suspended, ineligible, deleted or never there.
  for (const id of [SAM, host.id, crypto.randomUUID(), 'not-a-member']) {
    const response = await page.goto(`/people/${id}`);
    expect(response?.status()).toBe(404);
    await expect(page.getByText('This member is no longer active.')).toBeVisible();
    await expect(page.getByLabel('More actions')).toHaveCount(0);
  }
  await page.goto(`/people/${SAM}`);
  await expect(page.locator('main')).not.toContainText('Sam Suspended');
  await expectAccessible(page);
});

test('members see their own profile as others do', async ({ page, poster }) => {
  await page.goto(`/people/${poster.id}`);
  await expect(page.getByRole('heading', { level: 1 })).toHaveText('Pat Poster');
  await expect(page.getByText('This is how other members see you.')).toBeVisible();
  await expect(page.getByRole('link', { name: 'Edit profile' })).toHaveAttribute(
    'href',
    '/me/edit'
  );
  await expect(page.getByLabel('More actions')).toHaveCount(0);
  await expect(page.getByRole('region', { name: 'Organizing' })).toContainText(
    'Nothing coming up.'
  );
});
