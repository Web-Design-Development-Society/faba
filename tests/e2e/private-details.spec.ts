// Details for attendees only (ACT-09): the organizer and members going read them, and everyone else
// sees a note instead. They're never in the page or an Action's response for anyone else. The pgTAP
// tests cover who reads them through the Data API, moderators and hidden activities.
import { expect, expectAccessible, test } from './fixtures';

const LINK = 'https://meet.example.com/hike';
const DETAILS = `Gate code 4521. If it sticks, call from ${LINK}`;
const SECRET = 'Gate code 4521';
const NOTE = 'Exact location shared with attendees after you RSVP.';

test('the organizer adds details for attendees, sees them, and takes them off', async ({
  page,
  poster,
}) => {
  await page.goto('/activities/new');
  await page.getByLabel('What are you doing?').fill('Board game night');
  await page.getByRole('button', { name: 'Tomorrow' }).click();
  await page.getByLabel('Start time').fill('19:00');
  await page.getByLabel('Where?').fill('My place, near campus');
  await page.getByRole('radio', { name: 'Games' }).check();
  await page.getByText('More options').click();
  await page.getByLabel('Details for attendees only').fill(` ${DETAILS} `);
  await expectAccessible(page);
  // The draft leaves them out, since a shared computer keeps it.
  const draft = await page.evaluate(() => localStorage.getItem('faba-new-activity'));
  expect(draft).toContain('Board game night');
  expect(draft).not.toContain(SECRET);
  await page.getByRole('button', { name: 'Post activity' }).click();

  await expect(page.getByRole('status')).toHaveText('Posted!');
  const attendees = page.getByRole('region', { name: 'For attendees' });
  await expect(attendees.getByText(SECRET)).toBeVisible();
  await expect(attendees.getByRole('link', { name: LINK })).toHaveAttribute('href', LINK);
  await expect(page.getByText(NOTE)).toBeHidden();
  await expectAccessible(page);
  const { data } = await poster.admin
    .from('activities')
    .select('has_private_details, private:activity_private_details(details)')
    .eq('organizer_id', poster.id)
    .single();
  expect(data).toEqual({ has_private_details: true, private: { details: DETAILS } });

  await page.getByRole('link', { name: 'Edit', exact: true }).click();
  await expect(page.getByLabel('Details for attendees only')).toHaveValue(DETAILS);
  await page.getByLabel('Details for attendees only').fill('');
  await page.getByRole('button', { name: 'Save' }).click();
  await expect(page.getByRole('status')).toHaveText('Saved.');
  await expect(attendees).toHaveCount(0);
});

test("a member sees the note, the details after I'm in, and the note again after Maybe", async ({
  page,
  poster,
  host,
}) => {
  const id = await host.post({ private_details: DETAILS });
  // Asks for the details the way the page does after an answer changes.
  const ask = async () =>
    (
      await page.request.post('/_actions/activities.privateDetails', {
        data: { activity_id: id },
      })
    ).text();

  const response = await page.goto(`/activities/${id}`);
  expect(await response!.text()).not.toContain(SECRET);
  expect(await ask()).not.toContain(SECRET);
  const attendees = page.getByRole('region', { name: 'For attendees' });
  await expect(attendees.getByText(NOTE)).toBeVisible();
  await expectAccessible(page);

  await page.getByRole('button', { name: "I'm in" }).click();
  await expect(attendees.getByText(SECRET)).toBeVisible();
  await expect(attendees.getByRole('link', { name: LINK })).toHaveAttribute('href', LINK);
  await expect(attendees.getByText(NOTE)).toBeHidden();
  await expectAccessible(page);
  expect(await ask()).toContain(SECRET);

  await page.getByRole('button', { name: '✓ Going' }).click();
  await page
    .getByRole('dialog', { name: 'Are you going?' })
    .getByRole('button', { name: 'Maybe' })
    .click();
  await expect(attendees.getByText(NOTE)).toBeVisible();
  await expect(attendees).not.toContainText(SECRET);
  const { data } = await host.admin
    .from('rsvps')
    .select('status')
    .eq('activity_id', id)
    .eq('user_id', poster.id)
    .single();
  expect(data?.status).toBe('maybe');
  expect(await ask()).not.toContain(SECRET);
});

test.describe('without JavaScript', () => {
  test.use({ javaScriptEnabled: false });

  test("I'm in brings the page back with the details", async ({ page, poster, host }) => {
    const id = await host.post({ private_details: DETAILS });
    await page.goto(`/activities/${id}`);
    await expect(page.getByText(NOTE)).toBeVisible();
    await page.getByRole('button', { name: "I'm in" }).click();

    await expect(page.getByRole('status')).toHaveText("You're going.");
    await expect(page.getByText(SECRET)).toBeVisible();
    await expect(page.getByText(NOTE)).toBeHidden();
    const { data } = await host.admin
      .from('rsvps')
      .select('status')
      .eq('activity_id', id)
      .eq('user_id', poster.id)
      .single();
    expect(data?.status).toBe('going');
  });
});
