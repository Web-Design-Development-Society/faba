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
  await page.getByRole('region', { name: 'Host' }).getByRole('link', { name: 'Hana Host' }).click();
  await expect(page).toHaveURL(
    `/people/${host.id}?from=${encodeURIComponent(`/activities/${id}`)}`
  );
  await expect(page.getByRole('heading', { level: 1 })).toHaveText('Hana Host');
  await expect(page.getByText('Biology')).toBeVisible();
  await expect(page.getByText('I lead hikes.')).toBeVisible();
  // Each fact under a plain heading (UI-26).
  await expect(page.getByRole('region', { name: 'About' })).toContainText('I lead hikes.');
  await expect(page.getByRole('region', { name: 'Interests' }).getByRole('listitem')).toHaveText([
    'Outdoors',
    'Food & Socials',
  ]);
  const organizing = page.getByRole('region', { name: 'Organizing' });
  await expect(organizing.getByRole('article')).toHaveCount(1);
  await expect(organizing.getByRole('link', { name: 'Sunrise hike up the R' })).toHaveAttribute(
    'href',
    `/activities/${id}`
  );
  // She doesn't share her email, and her faculty type is never shown.
  await expect(page.getByRole('region', { name: 'Email' })).toHaveCount(0);
  await expect(page.locator('main')).not.toContainText(/part-time/i);
  await expectAccessible(page);

  await page.getByLabel('More actions').click();
  // Report keeps where the profile was opened from (PROF-03).
  await expect(page.getByRole('link', { name: 'Report' })).toHaveAttribute(
    'href',
    `/people/${host.id}/report?from=${encodeURIComponent(`/activities/${id}`)}`
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

test('a profile opened from an activity or a group goes back there, even after a report', async ({
  page,
  poster,
  host,
  crowd,
}) => {
  expect(poster.id).toBeTruthy();
  const title = `Back hike ${crypto.randomUUID().slice(0, 6)}`;
  const id = await host.post({ title });

  // From who's going, Back names the activity and goes there, so it isn't lost (PROF-03).
  await page.goto(`/activities/${id}`);
  await page
    .getByRole('region', { name: "Who's going" })
    .getByRole('link', { name: 'Hana Host' })
    .click();
  await expect(page.getByRole('heading', { level: 1 })).toHaveText('Hana Host');
  await expect(page.getByRole('link', { name: 'Back to Discover' })).toHaveCount(0);
  // Reporting them keeps it: the report goes back to the profile, which still goes back there.
  await page.getByLabel('More actions').click();
  await page.getByRole('link', { name: 'Report' }).click();
  await expect(page.getByRole('link', { name: 'Cancel' })).toHaveAttribute(
    'href',
    `/people/${host.id}?from=${encodeURIComponent(`/activities/${id}`)}`
  );
  await page.getByLabel('Unsafe').check();
  await page.getByRole('button', { name: 'Send report' }).click();
  await expect(page.getByRole('status')).toHaveText('Thanks, a moderator will review this.');
  await page.getByRole('link', { name: `Back to ${title}` }).click();
  await expect(page).toHaveURL(`/activities/${id}`);

  // From a group's members, Back goes to the group.
  const [owner] = await crowd(1);
  const name = `Back group ${crypto.randomUUID().slice(0, 6)}`;
  const { data: slug } = await owner.rpc('create_group', { name, category_id: 'games' });
  await page.goto(`/groups/${slug}`);
  await page.getByRole('button', { name: 'Join', exact: true }).click();
  await page
    .getByRole('region', { name: 'Members' })
    .getByRole('link', { name: 'Crowd Member 1' })
    .click();
  await page.getByRole('link', { name: `Back to ${name}` }).click();
  await expect(page).toHaveURL(`/groups/${slug}`);

  // Anywhere else, or a page they can't see, goes back to Discover.
  for (const from of ['https://example.com', `/activities/${crypto.randomUUID()}`, '/discover']) {
    await page.goto(`/people/${host.id}?from=${encodeURIComponent(from)}`);
    await expect(page.getByRole('link', { name: 'Back to Discover' })).toHaveAttribute(
      'href',
      '/discover'
    );
  }
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
