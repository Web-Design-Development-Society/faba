// "Maybe" (RSVP-05). The pgTAP tests cover the counts and who reads a maybe.
import { expect, expectAccessible, test } from './fixtures';

test('a member switches between going, maybe and not going', async ({ page, signInAs, host }) => {
  await signInAs('member');
  const id = await host.post();
  await page.goto(`/activities/${id}`);

  await page.getByRole('button', { name: "I'm in" }).click();
  await page.getByRole('button', { name: '✓ Going' }).click();
  const sheet = page.getByRole('dialog', { name: 'Are you going?' });
  await sheet.getByRole('button', { name: 'Maybe' }).click();
  await expect(sheet).toBeHidden();
  const maybe = page.getByRole('button', { name: 'Maybe', exact: true });
  await expect(maybe).toBeVisible();
  await expect(page.getByRole('status')).toHaveText("You're a maybe.");
  await expect(page.getByRole('button', { name: /1 going · 1 maybe$/ })).toBeVisible();

  // It's saved.
  await page.reload();
  await expect(maybe).toBeVisible();
  await maybe.click();
  await expect(sheet.getByRole('button', { name: 'Maybe' })).toHaveAttribute(
    'aria-pressed',
    'true'
  );
  await expectAccessible(page);
  await sheet.getByRole('button', { name: "Can't make it" }).click();
  await expect(page.getByRole('button', { name: "I'm in" })).toBeVisible();
  await expect(page.getByRole('button', { name: /1 going$/ })).toBeVisible();
});

test('the organizer sees who is a maybe', async ({ page, poster, crowd }) => {
  const { data: activity } = await poster.admin
    .from('activities')
    .insert({
      organizer_id: poster.id,
      category_id: 'games',
      title: 'Board game night',
      starts_at: new Date(Date.now() + 24 * 60 * 60 * 1000).toISOString(),
      location_name: 'Library',
      going_count: 1,
    })
    .select('id')
    .single();
  await poster.admin
    .from('rsvps')
    .insert({ activity_id: activity!.id, user_id: poster.id, status: 'going' });
  const [member] = await crowd(1);
  await member.rpc('rsvp', { activity_id: activity!.id, status: 'maybe' });

  await page.goto(`/activities/${activity!.id}`);
  await page.getByRole('button', { name: /1 going · 1 maybe$/ }).click();
  const list = page.getByRole('dialog', { name: "Who's going" });
  await expect(list.getByRole('heading', { name: 'Maybe' })).toBeVisible();
  await expect(list.getByRole('link', { name: 'Crowd Member 1' })).toBeVisible();
  await expectAccessible(page);
});
