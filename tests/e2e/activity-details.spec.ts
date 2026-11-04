// An activity's page (ACT-02).
import { addDays, rexburgDate, rexburgInstant } from '../../src/lib/time';
import { expect, expectAccessible, test } from './fixtures';

declare global {
  interface Window {
    shared?: ShareData;
    copied?: string;
  }
}

// Ada Admin, a persona with no photo.
const ADA = '00000000-0000-4000-8000-000000000004';

const tomorrow = addDays(rexburgDate(new Date()), 1);

test('a member sees what, when, where and who on one screen', async ({ page, signInAs, host }) => {
  await signInAs('member');
  const id = await host.post({
    starts_at: rexburgInstant(tomorrow, '07:00').toISOString(),
    ends_at: rexburgInstant(tomorrow, '09:30').toISOString(),
    description: 'Easy pace.\nTrail map: https://example.com/r-trail.',
    cost_note: 'Free',
  });
  await host.admin.from('rsvps').insert({ activity_id: id, user_id: ADA, status: 'going' });
  await host.admin.from('activities').update({ going_count: 2 }).eq('id', id);

  await page.goto(`/activities/${id}`);
  await expect(page.getByText('Outdoors')).toBeVisible();
  await expect(page.getByRole('heading', { level: 1 })).toHaveText('Sunrise hike up the R');
  // Intl puts thin spaces around the dash and a narrow no-break space before AM.
  await expect(page.getByText(/7:00\s–\s9:30\sAM$/)).toBeVisible();
  await expect(page.getByRole('link', { name: 'Open in Maps' })).toHaveAttribute(
    'href',
    /=R%20Mountain%20trailhead%2C%20Rexburg%2C%20ID$/
  );
  await expect(page.getByText('Cost: Free')).toBeVisible();
  await expect(page.getByText('2 going')).toBeVisible();
  await expect(page.getByRole('img', { name: 'Hana Host' })).toBeVisible();
  await expect(page.getByRole('img', { name: 'Ada Admin' })).toHaveText('AA');
  await expect(page.getByRole('link', { name: 'Hana Host' })).toHaveAttribute(
    'href',
    `/people/${host.id}`
  );
  // The full stop ends the sentence, not the address.
  await expect(page.getByRole('link', { name: 'https://example.com/r-trail' })).toHaveAttribute(
    'href',
    'https://example.com/r-trail'
  );

  await expect(page.getByRole('button', { name: "I'm in" })).toBeEnabled();
  await expect(page.getByRole('link', { name: 'Edit' })).toHaveCount(0);
  await page.getByLabel('More actions').click();
  await expect(page.getByRole('link', { name: 'Share' })).toHaveAttribute(
    'href',
    /^mailto:\?subject=Sunrise%20hike%20up%20the%20R&body=http/
  );
  await expect(page.getByRole('link', { name: 'Report' })).toHaveAttribute(
    'href',
    `/activities/${id}/report`
  );
  await expectAccessible(page);
});

test('Share opens the share sheet, or copies the link', async ({ page, signInAs, host }) => {
  await signInAs('member');
  const id = await host.post();
  await page.addInitScript(() => {
    Object.defineProperty(navigator, 'share', {
      configurable: true,
      value: async (data: ShareData) => void (window.shared = data),
    });
  });
  await page.goto(`/activities/${id}`);
  await page.getByLabel('More actions').click();
  await page.getByRole('link', { name: 'Share' }).click();
  await expect
    .poll(() => page.evaluate(() => window.shared))
    .toEqual({
      title: 'Sunrise hike up the R',
      url: page.url(),
    });

  // Without a share sheet. Later scripts run after earlier ones.
  await page.addInitScript(() => {
    Object.defineProperty(navigator, 'share', { configurable: true, value: undefined });
    Object.defineProperty(navigator, 'clipboard', {
      configurable: true,
      value: { writeText: async (text: string) => void (window.copied = text) },
    });
  });
  await page.reload();
  await page.getByLabel('More actions').click();
  await page.getByRole('link', { name: 'Share' }).click();
  await expect(page.getByRole('status')).toHaveText('Link copied.');
  await expect.poll(() => page.evaluate(() => window.copied)).toBe(page.url());
});

test('the organizer can edit, and sees why a moderator hid it', async ({ page, poster }) => {
  const { data: activity } = await poster.admin
    .from('activities')
    .insert({
      organizer_id: poster.id,
      category_id: 'games',
      title: 'Game night',
      starts_at: rexburgInstant(tomorrow, '19:00').toISOString(),
      location_name: 'Madison Library',
    })
    .select('id')
    .single();
  const id = activity!.id;

  await page.goto(`/activities/${id}`);
  await expect(page.getByText("You're hosting")).toBeVisible();
  await expect(page.getByRole('link', { name: 'Edit' })).toHaveAttribute(
    'href',
    `/activities/${id}/edit`
  );
  await expect(page.getByRole('button', { name: "I'm in" })).toHaveCount(0);
  // Organizers can't withdraw (RSVP-02).
  await expect(page.getByRole('button', { name: '✓ Going' })).toHaveCount(0);

  await poster.admin
    .from('activities')
    .update({ hidden_at: new Date().toISOString(), hidden_reason: 'Looks like spam.' })
    .eq('id', id);
  await page.reload();
  await expect(page.getByText('Hidden by a moderator: Looks like spam.')).toBeVisible();
  await expectAccessible(page);
});

test('a cancelled activity says why, and a hidden one is not available', async ({
  page,
  signInAs,
  host,
}) => {
  await signInAs('member');
  const cancelled = await host.post();
  const hidden = await host.post({ title: 'Business opportunity' });
  await host.admin
    .from('activities')
    .update({
      status: 'cancelled',
      cancelled_at: new Date().toISOString(),
      cancel_reason: 'Bad weather. We will reschedule.',
    })
    .eq('id', cancelled);
  await host.admin
    .from('activities')
    .update({ hidden_at: new Date().toISOString(), hidden_reason: 'Looks like spam.' })
    .eq('id', hidden);

  await page.goto(`/activities/${cancelled}`);
  await expect(page.getByText('Cancelled: Bad weather. We will reschedule.')).toBeVisible();
  await expect(page.getByRole('button', { name: "I'm in" })).toBeDisabled();
  await expect(page.getByText('This activity is cancelled.')).toBeVisible();
  await expectAccessible(page);

  const response = await page.goto(`/activities/${hidden}`);
  expect(response?.status()).toBe(404);
  await expect(page.getByRole('heading', { level: 1 })).toHaveText('Not available');
  await expect(page.getByText('Business opportunity')).toHaveCount(0);
});
