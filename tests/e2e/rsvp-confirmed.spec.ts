// RSVP confirmation (NOTIF-05). The pgTAP tests cover when it's made, deleted and made again.
import { formatWhen } from '../../src/lib/time';
import { expect, expectAccessible, test } from './fixtures';

test("I'm in puts a confirmation in Alerts, without the badge", async ({ page, poster, host }) => {
  expect(poster.id).toBeTruthy();
  const startsAt = new Date(Date.now() + 24 * 60 * 60 * 1000);
  startsAt.setSeconds(0, 0);
  const id = await host.post({ starts_at: startsAt.toISOString() });
  await page.goto(`/activities/${id}`);
  // ✓ Going shows before the RSVP is saved, so each answer waits for it.
  const saved = () =>
    page.waitForResponse((response) => response.url().includes('/_actions/rsvps.set'));
  let answered = saved();
  await page.getByRole('button', { name: "I'm in" }).click();
  expect((await answered).ok()).toBe(true);

  await page.goto('/notifications');
  const alerts = page
    .getByRole('navigation', { name: 'Main' })
    .getByRole('link', { name: /^Alerts/ });
  await expect(alerts).toHaveAccessibleName('Alerts');
  await expect(page.getByRole('button', { name: 'Mark all read' })).toHaveCount(0);
  await expect(page.getByRole('region', { name: 'New' })).toHaveCount(0);
  await expect(page.getByRole('region', { name: 'Earlier' }).getByRole('button')).toHaveText([
    new RegExp(`You're going on ${formatWhen(startsAt)}\\s*Sunrise hike up the R`),
  ]);
  await expectAccessible(page);

  // Can't make it takes it away.
  await page.goto(`/activities/${id}`);
  await page.getByRole('button', { name: '✓ Going' }).click();
  answered = saved();
  await page
    .getByRole('dialog', { name: 'Are you going?' })
    .getByRole('button', { name: "Can't make it" })
    .click();
  expect((await answered).ok()).toBe(true);
  await page.goto('/notifications');
  await expect(
    page.getByText("You're all caught up. We'll let you know when plans change.")
  ).toBeVisible();
});
