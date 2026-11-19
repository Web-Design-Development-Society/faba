// Dark mode (UI-33): when the device asks for it, FABA keeps its look in the dark. The page is a
// dark grey-blue, cards and paper are lighter greys, New activity's paper is a warm dark, and the
// orange stays as it is. FABA blue stays behind white words, and blue words are a lighter blue.
// Every page's words pass the same contrast rules as in the light.
import { expect, expectAccessible, paper, test, unreadableOnPage } from './fixtures';

test.use({ colorScheme: 'dark' });

const PAGE = 'rgb(15, 20, 27)';
const ORANGE = 'rgb(238, 109, 52)';
const HEADING = 'rgb(238, 242, 248)';

test('in the dark, the page, its cards and its paper are dark, and orange stays', async ({
  page,
  poster,
  host,
}) => {
  expect(poster.id).toBeTruthy();
  const id = await host.post();
  await page.goto('/discover');

  // The page and the browser's own parts, such as fields and scrollbars, follow the device.
  const html = page.locator('html');
  await expect(html).toHaveCSS('background-color', PAGE);
  await expect(html).toHaveCSS('color-scheme', 'light dark');
  await expect(page.locator('meta[name="theme-color"][media*="dark"]')).toHaveAttribute(
    'content',
    '#0f141b'
  );
  await expect(page.locator('meta[name="theme-color"][media*="light"]')).toHaveAttribute(
    'content',
    '#f4f7fb'
  );

  // A card is a lighter grey, with its title in near-white.
  const card = page.getByRole('article').first();
  expect(await paper(card)).toBe('1e2631');
  await expect(card.getByRole('heading')).toHaveCSS('color', HEADING);

  // Activities is still FABA blue paper with white words, and Groups has lighter blue words.
  const halves = page.getByRole('navigation', { name: 'Discover' });
  expect(await paper(halves.getByRole('link', { name: 'Activities' }))).toBe('0a74cf');
  await expect(halves.getByRole('link', { name: 'Groups' })).toHaveCSS(
    'color',
    'rgb(109, 179, 255)'
  );

  // The bar: the current tile is a dark blue, Discover's logo a light grey, and Post orange.
  const bar = page.getByRole('navigation', { name: 'Main' });
  const discover = bar.getByRole('link', { name: 'Discover' });
  expect(await paper(discover.locator('.tile'))).toBe('1c3754');
  await expect(discover.locator('.tile img')).toHaveCSS('filter', 'grayscale(1) brightness(1.7)');
  await expect(bar.locator('.post .square')).toHaveCSS('background-color', ORANGE);
  expect(await unreadableOnPage(page)).toEqual([]);
  await expectAccessible(page);

  // An activity is on dark paper.
  await page.goto(`/activities/${id}`);
  expect(await paper(page.locator('main'))).toBe('171d26');
  await expect(html).toHaveCSS('background-color', PAGE);
  await expectAccessible(page);

  // New activity is on warm dark paper, with the same orange edge and heading strip.
  await page.goto('/activities/new');
  const main = page.locator('main');
  expect(await paper(main)).toBe('221b16');
  await expect(main).toHaveCSS('border-top', `2px solid ${ORANGE}`);
  expect(await paper(page.getByRole('heading', { level: 1 }))).toBe('b8481a');
  expect(await unreadableOnPage(page)).toEqual([]);
  await expectAccessible(page);
});

test('in the dark, every page is readable', async ({ page, poster, host, crowd }) => {
  // Thirteen pages, each with axe, which takes WebKit on CI longer than the usual 30 seconds.
  test.slow();
  const id = await host.post();
  // An unread alert, for its card and dot on Alerts.
  await poster.admin
    .from('notifications')
    .insert({ recipient_id: poster.id, type: 'rsvp_confirmed', activity_id: id, payload: {} });
  const [owner] = await crowd(1);
  const { data: slug } = await owner.rpc('create_group', {
    name: `Dark group ${crypto.randomUUID().slice(0, 6)}`,
    category_id: 'games',
  });

  const found: string[] = [];
  const check = async (path: string) => {
    await page.goto(path);
    await expect(page.locator('html'), path).toHaveCSS('background-color', PAGE);
    for (const problem of await unreadableOnPage(page)) found.push(`${path}: ${problem}`);
    await expectAccessible(page);
  };
  for (const path of [
    '/plans',
    '/notifications',
    '/me',
    '/me/edit',
    '/search',
    '/groups',
    '/groups/new',
    `/groups/${slug}`,
    `/people/${host.id}`,
    `/people/${host.id}/report`,
    '/no-such-page',
  ]) {
    await check(path);
  }
  // A menu opens on a card, not on the page.
  await page.goto(`/people/${host.id}`);
  await page.getByLabel('More actions').click();
  await expect(page.getByRole('link', { name: 'Report' })).toBeVisible();
  await expectAccessible(page);

  // The pages for visitors too.
  await page.context().clearCookies();
  for (const path of ['/', '/auth/login']) await check(path);
  expect(found).toEqual([]);
});
