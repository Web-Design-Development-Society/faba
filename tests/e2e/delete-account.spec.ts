// Deleting my account (PROF-05). Pat Poster is a new account, which the test deletes for real.
import { expect, expectAccessible, test } from './fixtures';

const HOUR = 60 * 60 * 1000;
const inHours = (hours: number) => new Date(Date.now() + hours * HOUR).toISOString();

test('a member deletes their account from Me, after typing DELETE', async ({
  page,
  poster,
  signInAs,
}) => {
  const title = `Pickleball ${crypto.randomUUID().slice(0, 8)}`;
  // Pat organizes one coming up and one that's over, and is going to both, as organizers are.
  const { data: activities } = await poster.admin
    .from('activities')
    .insert([
      {
        organizer_id: poster.id,
        category_id: 'sports',
        title,
        starts_at: inHours(24),
        location_name: 'Hart courts',
        going_count: 1,
      },
      {
        organizer_id: poster.id,
        category_id: 'sports',
        title: `${title} (last week)`,
        starts_at: inHours(-7 * 24),
        location_name: 'Hart courts',
        going_count: 1,
      },
    ])
    .select('id');
  const [upcoming, past] = activities!.map(({ id }) => id);
  await poster.admin.from('rsvps').insert([
    { activity_id: upcoming, user_id: poster.id, status: 'going' },
    { activity_id: past, user_id: poster.id, status: 'going' },
  ]);
  try {
    await page.goto('/me');
    await page.getByRole('link', { name: 'Delete account' }).click();
    await expect(page).toHaveURL('/me/delete');
    await expect(page.getByRole('heading', { level: 1 })).toHaveText('Delete your account');
    await expect(page.getByText("It can't be undone.")).toBeVisible();
    await expectAccessible(page);

    await page.getByLabel('Type DELETE to confirm').fill('delete');
    await page.getByRole('button', { name: 'Delete my account' }).click();
    await expect(page.getByText('Type DELETE to confirm.')).toBeVisible();

    await page.getByLabel('Type DELETE to confirm').fill('DELETE');
    await page.getByRole('button', { name: 'Delete my account' }).click();
    await expect(page).toHaveURL('/goodbye');
    await expect(page.getByRole('heading', { level: 1 })).toHaveText('Your account is deleted');
    await expectAccessible(page);

    // Signed out, and gone.
    await page.goto('/me');
    await expect(page).toHaveURL(/^.*\/auth\/login/);
    const { data } = await poster.admin.auth.admin.getUserById(poster.id);
    expect(data.user).toBeNull();
    const { data: left } = await poster.admin
      .from('activities')
      .select('id, organizer_id, status, going_count')
      .in('id', [upcoming, past])
      .order('starts_at');
    expect(left).toEqual([
      { id: past, organizer_id: null, status: 'published', going_count: 0 },
      { id: upcoming, organizer_id: null, status: 'cancelled', going_count: 0 },
    ]);

    // Others see the cancelled one, from a former member.
    await signInAs('member');
    await page.goto(`/activities/${upcoming}`);
    await expect(page.getByText('Cancelled: Its organizer left FABA.')).toBeVisible();
    await expect(page.getByText('Hosted by Former member')).toBeVisible();
  } finally {
    // They have no organizer now, so deleting Pat's account doesn't find them.
    await poster.admin.from('activities').delete().in('id', [upcoming, past]);
  }
});
