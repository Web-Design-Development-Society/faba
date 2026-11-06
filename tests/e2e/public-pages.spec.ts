// About, the privacy notice, the guidelines and the disclaimers (INFO-01).
import { expect, expectAccessible, test } from './fixtures';

const UNOFFICIAL = "It isn't an official BYU-Idaho channel.";

test('visitors reach About, Privacy and the guidelines from every footer', async ({ page }) => {
  await page.goto('/');
  const footer = page.getByRole('contentinfo');
  await expect(footer).toContainText(UNOFFICIAL);

  for (const [link, path, heading] of [
    ['About', '/about', 'About FABA'],
    ['Privacy', '/privacy', 'Privacy notice'],
    ['Guidelines', '/guidelines', 'Community guidelines'],
  ]) {
    await footer.getByRole('link', { name: link }).click();
    await expect(page).toHaveURL(path);
    await expect(page.getByRole('heading', { level: 1 })).toHaveText(heading);
    await expect(footer).toContainText(UNOFFICIAL);
    await expectAccessible(page);
  }
});

test('the guidelines say who to contact, and carry the participation disclaimer', async ({
  page,
}) => {
  await page.goto('/guidelines');
  await expect(page.getByText('In an emergency, call 911')).toBeVisible();
  await expect(page.getByText('For an urgent safety concern')).toContainText('the FABA board');
  await expect(page.getByText('Join at your own risk.')).toBeVisible();
});

test('app pages ask search engines not to index them', async ({ page, signInAs }) => {
  const landing = await page.goto('/');
  expect(landing?.headers()['x-robots-tag']).toBe('noindex');
  await signInAs('member');
  const discover = await page.goto('/discover');
  expect(discover?.headers()['x-robots-tag']).toBe('noindex');
  await expect(page.getByRole('contentinfo')).toContainText(UNOFFICIAL);
});

test("Outdoors and Sports activities carry the participation disclaimer, and others don't", async ({
  page,
  signInAs,
  host,
}) => {
  await signInAs('member');
  const hike = await host.post();
  const games = await host.post({ title: 'Board game night', category_id: 'games' });

  await page.goto(`/activities/${hike}`);
  await expect(page.getByText('Join at your own risk.')).toBeVisible();
  await expectAccessible(page);

  await page.goto(`/activities/${games}`);
  await expect(page.getByRole('heading', { level: 1 })).toHaveText('Board game night');
  await expect(page.getByText('Join at your own risk.')).toHaveCount(0);
});
