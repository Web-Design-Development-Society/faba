// Suspending and reinstating a member (MOD-04). Other tests report at the same time, so each note
// has a tag.
import { expect, expectAccessible, test } from './fixtures';

test('a moderator suspends a reported member, then reinstates them from their profile', async ({
  page,
  signInAs,
  host,
}) => {
  await signInAs('moderator');
  const id = await host.post();
  const note = `Rude at the hike ${crypto.randomUUID().slice(0, 8)}`;
  // From someone who has since deleted their account, so it has no reporter.
  const { data: report } = await host.admin
    .from('reports')
    .insert({
      reporter_id: null,
      target_type: 'profile',
      target_id: host.id,
      reason: 'unsafe',
      note,
    })
    .select('id')
    .single();
  try {
    await page.goto('/mod');
    const item = page.getByRole('article').filter({ hasText: note });
    await item.getByRole('button', { name: 'Suspend member' }).click();
    const suspend = page.getByRole('dialog', { name: 'Suspend this member?' });
    await suspend.getByLabel('Reason, for the audit log').fill('Harassment');
    await suspend.getByRole('button', { name: 'Yes, suspend them' }).click();
    await expect(page).toHaveURL('/mod');
    await expect(page.getByRole('status')).toHaveText('Member suspended.');
    await expect(item).toHaveCount(0);
    const { data: suspended } = await host.admin
      .from('profiles')
      .select('status')
      .eq('id', host.id)
      .single();
    expect(suspended?.status).toBe('suspended');
    const { data: hidden } = await host.admin
      .from('activities')
      .select('hidden_reason')
      .eq('id', id)
      .single();
    expect(hidden?.hidden_reason).toBe('Its organizer was suspended.');

    await page.goto(`/people/${host.id}`);
    await expect(page.getByText('Suspended', { exact: true })).toBeVisible();
    await expect(page.getByLabel('More actions')).toHaveCount(0);
    await expectAccessible(page);
    await page.getByRole('button', { name: 'Reinstate' }).click();
    const reinstate = page.getByRole('dialog', { name: 'Reinstate this member?' });
    await reinstate.getByLabel('Reason, for the audit log').fill('Apologized to the group');
    await reinstate.getByRole('button', { name: 'Yes, reinstate them' }).click();
    await expect(page).toHaveURL(`/people/${host.id}`);
    await expect(page.getByRole('status')).toHaveText('Member reinstated.');
    await expect(page.getByText('Suspended', { exact: true })).toHaveCount(0);
    // Their activity stays hidden, for a moderator to unhide.
    const { data: still } = await host.admin
      .from('activities')
      .select('hidden_at')
      .eq('id', id)
      .single();
    expect(still?.hidden_at).not.toBeNull();
  } finally {
    await host.admin.from('reports').delete().eq('id', report!.id);
  }
});

test('a suspended member sees only Access paused, and can sign out', async ({ page, poster }) => {
  await poster.admin.from('profiles').update({ status: 'suspended' }).eq('id', poster.id);
  await page.goto('/discover');
  await expect(page).toHaveURL('/paused');
  await expect(page.getByRole('heading', { level: 1 })).toHaveText('Your access is paused');
  await expectAccessible(page);
  await page.goto('/me');
  await expect(page).toHaveURL('/paused');

  await page.getByRole('button', { name: 'Sign out' }).click();
  await expect(page).toHaveURL('/');
});

test('Access paused is only for suspended members', async ({ page, signInAs }) => {
  await signInAs('member');
  await page.goto('/paused');
  await expect(page).toHaveURL('/discover');
});
