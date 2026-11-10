// An activity as an .ics file for the member's own calendar (ACT-08). The unit tests cover the
// file's format: escaping, line folding, UTC times and an event without an end time.
import { expect, test } from './fixtures';

const DETAILS = 'Gate code 4521';

/** The file's text unfolded, as a calendar reads it. */
const unfolded = (file: string) => file.replace(/\r\n /g, '');

test('signed out, the .ics asks to sign in first', async ({ page, host }) => {
  const id = await host.post({ private_details: DETAILS });
  const response = await page.request.get(`/activities/${id}.ics`, { maxRedirects: 0 });

  expect(response.status()).toBe(302);
  expect(response.headers().location).toBe(
    `/auth/login?next=${encodeURIComponent(`/activities/${id}.ics`)}`
  );
  expect(await response.text()).not.toContain(DETAILS);
});

test('a member gets the activity, and its details for attendees once going', async ({
  page,
  poster,
  host,
}) => {
  const id = await host.post({
    description: 'Easy pace, about 3 miles.',
    private_details: DETAILS,
  });
  const download = () => page.request.get(`/activities/${id}.ics`);

  const response = await download();
  expect(response.status()).toBe(200);
  expect(response.headers()).toMatchObject({
    'content-type': 'text/calendar; charset=utf-8',
    'content-disposition': 'attachment; filename="sunrise-hike-up-the-r.ics"',
    'cache-control': 'private, no-store',
  });
  const file = unfolded(await response.text());
  expect(file).toContain(`\r\nUID:${id}\r\n`);
  expect(file).toContain('\r\nSUMMARY:Sunrise hike up the R\r\n');
  expect(file).toContain('\r\nLOCATION:R Mountain trailhead\r\n');
  expect(file).toContain('\r\nDESCRIPTION:Easy pace\\, about 3 miles.\\n\\n');
  expect(file).toMatch(new RegExp(`\r\nURL:http.+/activities/${id}\r\n`));
  expect(file).toContain('\r\nSTATUS:CONFIRMED\r\n');
  expect(file).not.toContain(DETAILS);

  await page.goto(`/activities/${id}`);
  await page.getByRole('button', { name: "I'm in" }).click();
  await expect(page.getByText(DETAILS)).toBeVisible();
  const { data } = await host.admin
    .from('rsvps')
    .select('status')
    .eq('activity_id', id)
    .eq('user_id', poster.id)
    .single();
  expect(data?.status).toBe('going');

  expect(unfolded(await (await download()).text())).toContain(`\\n\\nFor attendees: ${DETAILS}`);
});

test("a moderator who isn't going gets it without the details", async ({
  page,
  signInAs,
  host,
}) => {
  await signInAs('moderator');
  const id = await host.post({ private_details: DETAILS });
  const response = await page.request.get(`/activities/${id}.ics`);

  expect(response.status()).toBe(200);
  expect(await response.text()).not.toContain(DETAILS);
});

test("an activity the member can't see isn't found", async ({ page, signInAs, host }) => {
  await signInAs('member');
  const id = await host.post({ private_details: DETAILS });
  await host.admin
    .from('activities')
    .update({ hidden_at: new Date().toISOString(), hidden_reason: 'Selling tickets' })
    .eq('id', id);

  const hidden = await page.request.get(`/activities/${id}.ics`);
  expect(hidden.status()).toBe(404);
  expect(await hidden.text()).not.toContain(DETAILS);
  expect((await page.request.get('/activities/not-an-id.ics')).status()).toBe(404);
});
