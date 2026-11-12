// An internal WCAG 2.2 AA sweep (A11Y-01, run in place of an outside audit). It checks each page in
// light and dark themes with every axe rule for WCAG 2.0 and 2.2 at AA, at every impact level, and
// checks that a 320 px screen has no sideways scroll (design document section 7.14).
import AxeBuilder from '@axe-core/playwright';
import { expect, test } from './fixtures';

const RULES = ['wcag2a', 'wcag2aa', 'wcag21aa', 'wcag22aa'];

async function problems(page: import('@playwright/test').Page) {
  const { violations } = await new AxeBuilder({ page }).withTags(RULES).analyze();
  return violations.map(
    ({ id, impact, help, nodes }) =>
      `${id} (${impact}): ${help} at ${nodes.map((n) => n.target.join(' ')).join(', ')}`
  );
}

test.describe.configure({ mode: 'serial' });

test('signed-out pages pass in both themes', async ({ page }) => {
  const found: string[] = [];
  for (const scheme of ['light', 'dark'] as const) {
    await page.emulateMedia({ colorScheme: scheme });
    for (const path of ['/', '/about', '/privacy', '/guidelines', '/auth/login']) {
      await page.goto(path);
      for (const p of await problems(page)) found.push(`${scheme} ${path}: ${p}`);
    }
  }
  expect(found).toEqual([]);
});

test('member pages pass in both themes, and reflow at 320 px', async ({
  page,
  poster,
  signInAs,
}) => {
  const { data: activity } = await poster.admin
    .from('activities')
    .insert({
      organizer_id: poster.id,
      category_id: 'games',
      title: 'Sweep night',
      starts_at: new Date(Date.now() + 24 * 60 * 60 * 1000).toISOString(),
      location_name: 'Library',
    })
    .select('id')
    .single();
  const { data: group } = await poster.admin
    .from('groups')
    .insert({
      slug: `sweep-${crypto.randomUUID().slice(0, 6)}`,
      name: 'Sweep group',
      category_id: 'games',
      join_policy: 'open',
      owner_id: poster.id,
    })
    .select('slug')
    .single();
  await signInAs('member');

  const paths = [
    '/discover',
    '/plans',
    '/search',
    '/me',
    '/me/edit',
    '/me/notifications',
    '/notifications',
    '/calendar',
    '/leagues/new',
    `/activities/${activity!.id}`,
    `/activities/${activity!.id}/edit`,
    '/groups/new',
    `/groups/${group!.slug}`,
    `/groups/${group!.slug}/members`,
  ];

  const found: string[] = [];
  for (const scheme of ['light', 'dark'] as const) {
    await page.emulateMedia({ colorScheme: scheme });
    for (const path of paths) {
      await page.goto(path);
      for (const p of await problems(page)) found.push(`${scheme} ${path}: ${p}`);
    }
  }

  await page.emulateMedia({ colorScheme: 'light' });
  await page.setViewportSize({ width: 320, height: 640 });
  for (const path of paths) {
    await page.goto(path);
    const overflow = await page.evaluate(
      () => document.documentElement.scrollWidth - document.documentElement.clientWidth
    );
    if (overflow > 0) found.push(`320px ${path}: scrolls sideways by ${overflow}px`);
  }

  expect(found).toEqual([]);
});

test('the skip link is the first focusable thing, and it moves focus into the content', async ({
  page,
}) => {
  await page.goto('/about');
  // Safari doesn't Tab to links by default, so this checks the order in the page, not the keys.
  const firstFocusable = await page.evaluate(() => {
    const el = document.querySelector('body a[href], body button, body input, body [tabindex]');
    return el?.getAttribute('href') ?? el?.tagName ?? '';
  });
  expect(firstFocusable).toBe('#content');
  await page.getByRole('link', { name: 'Skip to content' }).focus();
  await page.keyboard.press('Enter');
  expect(new URL(page.url()).hash).toBe('#content');
});
