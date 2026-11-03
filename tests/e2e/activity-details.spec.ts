// An activity's page (ACT-02).
import { addDays, rexburgDate, rexburgInstant } from '../../src/lib/time';
import { expect, expectAccessible, test } from './fixtures';

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

  await expect(page.getByRole('button', { name: "I'm in" })).toBeDisabled();
  await expectAccessible(page);
});
