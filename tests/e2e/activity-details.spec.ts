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
  await expect(page.getByRole('region', { name: 'Cost' })).toContainText('Free');
  await expect(page.getByText('2 going')).toBeVisible();
  // Everyone going is on the page (UI-21), each with their face or initials beside their name.
  const who = page.getByRole('region', { name: "Who's going" });
  await expect(who.getByRole('link', { name: 'Hana Host' })).toBeVisible();
  await expect(who.getByRole('listitem').filter({ hasText: 'Ada Admin' })).toContainText('AA');
  await expect(
    page.getByRole('region', { name: 'Host' }).getByRole('link', { name: 'Hana Host' })
  ).toHaveAttribute('href', `/people/${host.id}`);
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

test('each fact is under a plain heading on paper, the time and place big with their links at the right', async ({
  page,
  signInAs,
  host,
}) => {
  await signInAs('member');
  const id = await host.post({
    starts_at: rexburgInstant(tomorrow, '07:00').toISOString(),
    location_name: 'Hidden Valley Park, north trailhead parking lot by the river',
    description: 'Easy pace.',
  });

  await page.goto(`/activities/${id}`);
  // On cream paper, in roomy 17 px text (UI-26).
  const main = page.locator('main');
  await expect(main).toHaveCSS('background-color', 'rgb(247, 244, 236)');
  await expect(main).toHaveCSS('font-size', '17px');

  // Each fact under a plain heading, one after another, all the same size (UI-21, UI-26).
  const order = ['Date and time', 'Location', 'Host', 'Details', "Who's going", 'Category'];
  const sizes = new Set<string>();
  let above = 0;
  for (const name of order) {
    const heading = page.getByRole('heading', { name, level: 2, exact: true });
    const { y } = (await heading.boundingBox())!;
    expect(y).toBeGreaterThan(above);
    above = y;
    sizes.add(await heading.evaluate((el) => getComputedStyle(el).fontSize));
  }
  expect(sizes.size).toBe(1);

  // The time and the place are big, with no icons.
  const when = page.getByRole('region', { name: 'Date and time' });
  const where = page.getByRole('region', { name: 'Location' });
  const time = when.getByText(/7:00\sAM$/);
  const place = where.getByText('Hidden Valley Park, north trailhead parking lot by the river');
  for (const big of [time, place]) {
    const size = await big.evaluate((el) => parseFloat(getComputedStyle(el).fontSize));
    expect(size).toBeGreaterThanOrEqual(20);
  }
  for (const part of [when, where]) await expect(part.locator('svg')).toHaveCount(0);
  // Add to calendar and Open in Maps are quiet words at the right of their headings, 44 px tall.
  const mainBox = (await main.boundingBox())!;
  for (const [part, link] of [
    [when, when.getByRole('button', { name: 'Add to calendar' })],
    [where, where.getByRole('link', { name: 'Open in Maps' })],
  ] as const) {
    const [heading, b] = [
      (await part.getByRole('heading').boundingBox())!,
      (await link.boundingBox())!,
    ];
    expect(b.x).toBeGreaterThan(heading.x + heading.width - 1);
    expect(mainBox.x + mainBox.width - (b.x + b.width)).toBeLessThan(32);
    expect(b.height).toBeGreaterThanOrEqual(44);
    await expect(link).toHaveCSS('background-color', 'rgba(0, 0, 0, 0)');
    await expect(link).toHaveCSS('border-top-style', 'none');
  }
  await expect(
    page.getByRole('region', { name: 'Host' }).getByRole('link', { name: 'Hana Host' })
  ).toBeVisible();

  // Everyone going is on the page, with no tap needed.
  const who = page.getByRole('region', { name: "Who's going" });
  await expect(who.locator('.going')).toHaveText('1 going', { useInnerText: true });
  await expect(who.getByRole('link', { name: 'Hana Host' })).toBeVisible();
  // Only those who can manage attendees have the button for it.
  await expect(who.getByRole('button', { name: 'Manage attendees' })).toHaveCount(0);

  // The category is a chip with its icon, in its own part (UI-05, UI-26).
  const category = page.getByRole('region', { name: 'Category' });
  await expect(category.locator('svg')).toHaveCount(1);
  await expect(category.getByText('Outdoors')).toBeVisible();

  // The comment box is the paper's width, inside its padding.
  const box = page.getByLabel('Ask a question or leave a comment');
  const [boxWidth, partWidth] = [
    (await box.boundingBox())!.width,
    (await when.boundingBox())!.width,
  ];
  expect(Math.abs(boxWidth - partWidth)).toBeLessThanOrEqual(1);
  expect(await page.evaluate(() => document.documentElement.scrollWidth <= window.innerWidth)).toBe(
    true
  );
  await expectAccessible(page);
});
