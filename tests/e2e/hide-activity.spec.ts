// Hiding and unhiding an activity (MOD-03). The member's and organizer's sides are in
// activity-details.spec.ts. Other tests report at the same time, so each title has a tag.
import { expect, expectAccessible, test } from './fixtures';

const named = (title: string) => `${title} ${crypto.randomUUID().slice(0, 8)}`;

test('a moderator hides a reported activity from the queue', async ({ page, signInAs, host }) => {
  await signInAs('moderator');
  const title = named('Ticket sale');
  const id = await host.post({ title });
  // From someone who has since deleted their account, so it has no reporter.
  const { data: report } = await host.admin
    .from('reports')
    .insert({ reporter_id: null, target_type: 'activity', target_id: id, reason: 'spam' })
    .select('id')
    .single();
  try {
    await page.goto('/mod');
    const item = page.getByRole('article').filter({ hasText: title });
    await item.getByRole('button', { name: 'Hide content' }).click();
    const sheet = page.getByRole('dialog', { name: 'Hide this activity?' });
    await expect(sheet).toContainText('Its organizer sees your reason');
    await expectAccessible(page);
    await sheet.getByLabel('Reason, for the audit log').fill('Selling tickets');
    await sheet.getByRole('button', { name: 'Hide activity' }).click();
    await expect(page).toHaveURL('/mod');
    await expect(page.getByRole('status')).toHaveText('Activity hidden.');
    await expect(page.getByRole('article').filter({ hasText: title })).toHaveCount(0);

    const { data: activity } = await host.admin
      .from('activities')
      .select('hidden_at, hidden_reason')
      .eq('id', id)
      .single();
    expect(activity?.hidden_at).not.toBeNull();
    expect(activity?.hidden_reason).toBe('Selling tickets');
    const { data: actioned } = await host.admin
      .from('reports')
      .select('status')
      .eq('id', report!.id)
      .single();
    expect(actioned?.status).toBe('actioned');
  } finally {
    await host.admin.from('reports').delete().eq('id', report!.id);
  }
});

test('a moderator unhides an activity from its page', async ({ page, signInAs, host }) => {
  await signInAs('moderator');
  const title = named('Bake sale');
  const id = await host.post({ title });
  await host.admin
    .from('activities')
    .update({ hidden_at: new Date().toISOString(), hidden_reason: 'Selling tickets' })
    .eq('id', id);

  await page.goto(`/activities/${id}`);
  await expect(page.getByText('Hidden by a moderator: Selling tickets')).toBeVisible();
  // The organizer's note isn't for moderators, and nobody RSVPs while it's hidden.
  await expect(page.getByText('Contact the FABA board')).toHaveCount(0);
  await expect(page.getByText('This activity is hidden.')).toBeVisible();
  await expect(page.getByRole('button', { name: "I'm in" })).toBeDisabled();
  await expectAccessible(page);

  await page.getByRole('button', { name: 'Unhide' }).click();
  const sheet = page.getByRole('dialog', { name: 'Unhide this activity?' });
  await sheet.getByLabel('Reason, for the audit log').fill('The organizer took the sale out');
  await sheet.getByRole('button', { name: 'Yes, unhide it' }).click();
  await expect(page).toHaveURL(`/activities/${id}`);
  await expect(page.getByRole('status')).toHaveText('Activity unhidden.');
  await expect(page.getByText('Hidden by a moderator')).toHaveCount(0);
  await expect(page.getByRole('button', { name: "I'm in" })).toBeEnabled();
});
