// Who's going (RSVP-03).
import { expect, expectAccessible, test } from './fixtures';

// Personas: Ada Admin, and Sam Suspended.
const ADA = '00000000-0000-4000-8000-000000000004';
const SAM = '00000000-0000-4000-8000-000000000005';

test("the going row opens who's going, with the organizer first", async ({
  page,
  signInAs,
  host,
}) => {
  await signInAs('member');
  const id = await host.post();
  await host.admin.from('profiles').update({ department: 'Biology' }).eq('id', host.id);
  // Ada said I'm in before Hana posted, and Sam is suspended. Apart, since rows inserted together
  // get null for a column that another row sets.
  await host.admin
    .from('rsvps')
    .insert({ activity_id: id, user_id: ADA, status: 'going', created_at: '2020-01-01T00:00:00Z' });
  await host.admin.from('rsvps').insert({ activity_id: id, user_id: SAM, status: 'going' });
  await host.admin.from('activities').update({ going_count: 3 }).eq('id', id);

  await page.goto(`/activities/${id}`);
  const row = page.getByRole('button', { name: /3 going$/ });
  await row.click();
  const sheet = page.getByRole('dialog', { name: "Who's going" });
  const people = sheet.getByRole('listitem');
  await expect(people).toHaveCount(2);
  await expect(people.first()).toContainText('Hana Host');
  await expect(people.first()).toContainText('Organizer');
  await expect(people.first()).toContainText('Biology');
  await expect(people.nth(1)).toContainText('Ada Admin');
  await expect(sheet.getByRole('link', { name: 'Hana Host' })).toHaveAttribute(
    'href',
    `/people/${host.id}`
  );
  await expect(sheet.getByRole('link', { name: 'Show all' })).toHaveCount(0);
  await expectAccessible(page);

  await page.keyboard.press('Escape');
  await expect(sheet).toBeHidden();
  await expect(row).toBeFocused();
});

// A phone has no Escape, so the sheet has a Close button, and a tap on the dimmed page above it
// closes it too.
test("who's going closes with Close, or a tap outside it", async ({ page, signInAs, host }) => {
  await signInAs('member');
  const id = await host.post();
  await page.goto(`/activities/${id}`);
  const row = page.getByRole('button', { name: /1 going$/ });
  const sheet = page.getByRole('dialog', { name: "Who's going" });

  await row.click();
  const close = sheet.getByRole('button', { name: 'Close' });
  // All of it is on screen, not cut off at the right edge.
  await expect(close).toBeInViewport({ ratio: 1 });
  await close.click();
  await expect(sheet).toBeHidden();
  await expect(row).toBeFocused();

  await row.click();
  await expect(sheet).toBeVisible();
  await page.mouse.click(10, 10);
  await expect(sheet).toBeHidden();
});

// The browsers the tests run in have closedby, so here it's taken away, as an older Safari would
// be: only src/scripts/sheets.ts can close the sheet on a tap outside.
test('a tap outside closes a sheet in a browser without closedby', async ({
  page,
  signInAs,
  host,
}) => {
  await page.addInitScript(() => {
    delete (HTMLDialogElement.prototype as { closedBy?: string }).closedBy;
  });
  await signInAs('member');
  const id = await host.post();
  await page.goto(`/activities/${id}`);
  const sheet = page.getByRole('dialog', { name: "Who's going" });
  // By its id, since a closed sheet is hidden, and roles only find what's shown.
  await page.locator('dialog#going').evaluate((dialog) => dialog.removeAttribute('closedby'));

  await page.getByRole('button', { name: /1 going$/ }).click();
  await expect(sheet).toBeVisible();
  // A tap on the sheet itself leaves it open.
  await sheet.getByRole('heading', { name: "Who's going" }).click();
  await expect(sheet).toBeVisible();
  await page.mouse.click(10, 10);
  await expect(sheet).toBeHidden();
});

test("after I'm in, who's going has the member in it", async ({ page, poster, host }) => {
  const id = await host.post();
  await page.goto(`/activities/${id}`);
  await page.getByRole('button', { name: "I'm in" }).click();
  await page.getByRole('button', { name: /2 going$/ }).click();
  const sheet = page.getByRole('dialog', { name: "Who's going" });
  await expect(sheet.getByRole('listitem')).toHaveCount(2);
  await expect(sheet.getByRole('link', { name: 'Pat Poster' })).toHaveAttribute(
    'href',
    `/people/${poster.id}`
  );
  await page.keyboard.press('Escape');

  await page.getByRole('button', { name: '✓ Going' }).click();
  await page.getByRole('button', { name: "Can't make it" }).click();
  await page.getByRole('button', { name: /1 going$/ }).click();
  await expect(sheet.getByRole('listitem')).toHaveCount(1);
  await expect(sheet.getByRole('listitem')).toContainText('Hana Host');
});

test('with more than 50 going, Show all lists everyone on a page', async ({
  page,
  signInAs,
  host,
}) => {
  await signInAs('member');
  const id = await host.post();
  // As if 60 were going. Only Hana and Ada are.
  await host.admin.from('rsvps').insert({ activity_id: id, user_id: ADA, status: 'going' });
  await host.admin.from('activities').update({ going_count: 60 }).eq('id', id);

  await page.goto(`/activities/${id}`);
  await page.getByRole('button', { name: /60 going$/ }).click();
  await page.getByRole('link', { name: 'Show all' }).click();
  await expect(page).toHaveURL(`/activities/${id}/going`);
  await expect(page.getByRole('heading', { level: 1 })).toHaveText("Who's going");
  await expect(page.getByRole('listitem')).toHaveCount(2);
  await expect(page.getByRole('listitem').first()).toContainText('Hana Host');
  await expectAccessible(page);

  await page.getByRole('link', { name: 'Back to Sunrise hike up the R' }).click();
  await expect(page).toHaveURL(`/activities/${id}`);
});

test.describe('without JavaScript', () => {
  test.use({ javaScriptEnabled: false });

  test("the going row opens who's going", async ({ page, signInAs, host }) => {
    await signInAs('member');
    const id = await host.post();
    await page.goto(`/activities/${id}`);
    await page.getByRole('button', { name: /1 going$/ }).click();
    const sheet = page.getByRole('dialog', { name: "Who's going" });
    await expect(sheet.getByRole('listitem')).toHaveCount(1);
    await expect(sheet.getByRole('listitem')).toContainText('Hana Host');
    // Close is a dialog form, so it works without JavaScript too.
    await sheet.getByRole('button', { name: 'Close' }).click();
    await expect(sheet).toBeHidden();
  });
});
