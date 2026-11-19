// FABA's look (UI-02, UI-14, UI-16, UI-18, UI-25, UI-29): the bottom bar keeps its five items, each
// with a line icon in a tile over its label, and the current tab and chosen date are FABA blue. The
// cut-paper look puts headings in Anton, in capitals by CSS, and each tab on a piece of paper with a
// shadow, on a solid, nearly white grey that text sits straight on, readable all the way down. New
// activity's form is on warm paper. Every corner is square but faces. The main tabs' headings are
// for screen readers only, since the bottom bar shows which page it is.
import type { Locator, Page } from '@playwright/test';
import { expect, expectAccessible, expectSquare, paper, test, unreadableOnPage } from './fixtures';

const BLUE = 'rgb(0, 108, 194)';
// The page's solid background (UI-29).
const PAGE = 'rgb(244, 246, 248)';
const SKY = 'rgb(207, 225, 250)';
// New and Edit activity's paper, and the orange of Post (UI-25).
const ORANGE = 'rgb(238, 109, 52)';
const WARM_PAPER = 'rgb(255, 249, 244)';

test('selected things are FABA blue, and the bar keeps its five items', async ({
  page,
  signInAs,
}) => {
  await signInAs('member');
  await page.goto('/discover');

  const bar = page.getByRole('navigation', { name: 'Main' });
  await expect(bar.getByRole('link')).toHaveText(['Discover', 'Plans', 'Post', /^Alerts/, 'Me']);
  // Discover's tile has the FABA logo in greyscale, and the other four keep their icons (UI-28).
  const discover = bar.getByRole('link', { name: 'Discover' });
  await expect(discover.locator('svg')).toHaveCount(0);
  const mark = discover.locator('.tile img');
  await expect(mark).toHaveAttribute('src', '/brand/faba-mark.png');
  await expect(mark).toHaveAttribute('alt', '');
  await expect(mark).toHaveCSS('filter', 'grayscale(1) brightness(0.7)');
  await expect
    .poll(() => mark.evaluate((img: HTMLImageElement) => img.naturalWidth))
    .toBeGreaterThan(0);
  for (const name of ['Plans', 'Post', /^Alerts/, 'Me']) {
    await expect(bar.getByRole('link', { name }).locator('svg')).toHaveCount(1);
  }
  // The current tab's tile is light blue, and it's underlined, so it isn't color alone.
  const here = bar.getByRole('link', { name: 'Discover' });
  await expect(here).toHaveAttribute('aria-current', 'page');
  await expect(here.locator('.tile')).toHaveCSS('background-color', SKY);
  await expect(bar.getByRole('link', { name: 'Plans' }).locator('.tile')).toHaveCSS(
    'background-color',
    'rgb(255, 255, 255)'
  );
  // Post is an orange square that rises above the bar, as warm as New activity (UI-14, UI-25).
  await expect(bar.locator('.post .square')).toHaveCSS('background-color', ORANGE);
  // A darker orange on hover, not navy.
  await bar.locator('.post').hover();
  await expect(bar.locator('.post .square')).toHaveCSS('background-color', 'rgb(201, 79, 28)');

  // Activities is on FABA blue paper, and Groups on light blue.
  const halves = page.getByRole('navigation', { name: 'Discover' });
  expect(await paper(halves.getByRole('link', { name: 'Activities' }))).toBe('006cc2');
  // The other is white with FABA blue words (UI-29).
  expect(await paper(halves.getByRole('link', { name: 'Groups' }))).toBe('ffffff');
  await expect(halves.getByRole('link', { name: 'Groups' })).toHaveCSS('color', BLUE);
  // Any time, the date chosen until another is, is FABA blue in the Date list.
  const filters = page.getByRole('navigation', { name: 'Filters' });
  await filters.locator('summary', { hasText: /^Date/ }).click();
  await expect(filters.getByRole('link', { name: 'Any time' })).toHaveCSS('background-color', BLUE);
  await page.keyboard.press('Escape');

  // The mark and the wordmark go to Discover, and Search is an icon button with its name.
  await expect(page.getByRole('link', { name: 'FABA' })).toHaveAttribute('href', '/discover');
  await expect(page.getByRole('link', { name: 'Search' })).toBeVisible();
  await expectAccessible(page);
});

test('headers start each word with a capital, while buttons and tabs stay in capitals', async ({
  page,
  poster,
  host,
}) => {
  expect(poster.id).toBeTruthy();
  const id = await host.post();
  // Headers: a day's label and a card's title on Discover, and a page's headings (UI-30).
  await page.goto('/discover');
  const feed = page.locator('[data-feed]');
  await expect(feed.locator('[data-day] > h3').first()).toHaveCSS('text-transform', 'capitalize');
  await expect(feed.getByRole('article').first().getByRole('heading')).toHaveCSS(
    'text-transform',
    'capitalize'
  );
  // Not headers: the tabs, the filter buttons, a card's date and the bottom bar.
  await expect(
    page.getByRole('navigation', { name: 'Discover' }).getByRole('link', { name: 'Activities' })
  ).toHaveCSS('text-transform', 'uppercase');
  await expect(
    page.getByRole('navigation', { name: 'Filters' }).locator('summary').first()
  ).toHaveCSS('text-transform', 'uppercase');
  await expect(feed.getByRole('article').first().locator('.date')).toHaveCSS(
    'text-transform',
    'uppercase'
  );
  await expect(
    page.getByRole('navigation', { name: 'Main' }).getByRole('link', { name: 'Plans' })
  ).toHaveCSS('text-transform', 'uppercase');

  await page.goto(`/activities/${id}`);
  await expect(page.getByRole('heading', { level: 1 })).toHaveCSS('text-transform', 'capitalize');
  await expect(page.getByRole('heading', { name: 'Date and time', level: 2 })).toHaveCSS(
    'text-transform',
    'capitalize'
  );
  // A button stays in capitals (UI-22).
  await expect(page.getByRole('button', { name: "I'm in" })).toHaveCSS(
    'text-transform',
    'uppercase'
  );
});

test("the main tabs' headings are for screen readers, and New activity keeps its banner, warm", async ({
  page,
  signInAs,
}) => {
  await signInAs('member');
  // The bottom bar shows which page it is, so Discover, its Groups half, Plans, Alerts and Me have no
  // banner. Each keeps its heading for screen readers, taking no room on screen (UI-18).
  for (const [path, name] of [
    ['/discover', 'Discover'],
    ['/groups', 'Discover'],
    ['/plans', 'Plans'],
    ['/notifications', 'Alerts'],
    ['/me', 'Me'],
  ]) {
    await page.goto(path);
    const hidden = page.getByRole('heading', { level: 1 });
    await expect(hidden).toHaveText(name);
    const box = (await hidden.boundingBox())!;
    expect(box.width * box.height).toBeLessThanOrEqual(1);
    await expect(hidden).toHaveCSS('box-shadow', 'none');
    // Even a short page, such as Alerts with none, is as tall as the screen, so its background
    // fills it.
    expect(
      await page.evaluate(
        () => document.documentElement.getBoundingClientRect().height >= window.innerHeight
      )
    ).toBe(true);
  }
  // New activity keeps its banner: big, in Anton, each word starting with a capital (UI-30).
  await page.goto('/activities/new');
  const heading = page.getByRole('heading', { level: 1 });
  // Capitals come from CSS, so the page, screen readers and search keep the words as written.
  await expect(heading).toHaveText('New activity');
  await expect(heading).toHaveCSS('text-transform', 'capitalize');
  await expect(heading).toHaveCSS('font-family', /^Anton/);
  expect(await page.evaluate(() => document.fonts.check('48px Anton'))).toBe(true);
  // On one line at every width, and as big as a heading on a phone should be.
  const size = parseFloat(await heading.evaluate((el) => getComputedStyle(el).fontSize));
  expect(size).toBeGreaterThanOrEqual(36);
  expect((await heading.boundingBox())!.height).toBeLessThan(size * 1.6);
  // It sits on its own strip of paper, with square corners and a shadow (UI-16): white words on a
  // deeper orange, 5.3:1, so it pops (UI-32).
  expect(await paper(heading)).toBe('b8481a');
  await expect(heading).toHaveCSS('color', 'rgb(255, 255, 255)');
  await expectSquare(heading);
  // New activity is warm (UI-25): its form is on a piece of warm paper, on the same solid grey as
  // every other page, with no gradient (UI-29).
  const main = page.locator('main');
  const html = page.locator('html');
  await expect(main).toHaveCSS('background-color', WARM_PAPER);
  // A thin orange edge, the Post button's orange (UI-32).
  await expect(main).toHaveCSS('border-top', `2px solid ${ORANGE}`);
  await expect(main).toHaveCSS('box-shadow', 'none');
  await expect(main).toHaveCSS('border-top-left-radius', '0px');
  await expect(html).toHaveCSS('background-image', 'none');
  await expect(html).toHaveCSS('background-color', PAGE);
  expect(await unreadableOnPage(page)).toEqual([]);
  expect(
    await page.evaluate(() => getComputedStyle(document.documentElement, '::before').content)
  ).toBe('none');
  expect(await page.evaluate(() => document.documentElement.scrollWidth <= window.innerWidth)).toBe(
    true
  );
  await expectAccessible(page);

  // Every other page is the same solid grey, with no gradient or photo (UI-29), and the content
  // sits straight on it.
  await page.goto('/discover');
  await expect(main).toHaveCSS('background-color', 'rgba(0, 0, 0, 0)');
  await expect(html).toHaveCSS('background-image', 'none');
  await expect(html).toHaveCSS('background-color', PAGE);
});

test("Edit activity is warm too, for its organizer, but not when they can't edit", async ({
  page,
  poster,
  host,
}) => {
  const { data } = await poster.admin
    .from('activities')
    .insert({
      organizer_id: poster.id,
      category_id: 'games',
      title: 'Warm game night',
      starts_at: new Date(Date.now() + 24 * 60 * 60 * 1000).toISOString(),
      location_name: 'Library',
    })
    .select('id')
    .single();
  await page.goto(`/activities/${data!.id}/edit`);
  await expect(page.getByRole('heading', { level: 1 })).toHaveText('Edit activity');
  await expect(page.locator('html')).toHaveCSS('background-color', PAGE);
  await expect(page.locator('main')).toHaveCSS('background-color', WARM_PAPER);
  await expect(page.locator('main')).toHaveCSS('border-top', `2px solid ${ORANGE}`);
  // Back sits on the warm paper too.
  expect(await unreadableOnPage(page)).toEqual([]);
  await expectAccessible(page);

  // Someone else's activity says they can't edit it, with no warm paper.
  const theirs = await host.post();
  await page.goto(`/activities/${theirs}/edit`);
  await expect(page.getByText('Only the organizer can edit this activity.')).toBeVisible();
  await expect(page.locator('main')).toHaveCSS('background-color', 'rgba(0, 0, 0, 0)');
});

test('an activity, a group, a member and the short forms are on cream paper, read top to bottom', async ({
  page,
  poster,
  host,
}) => {
  const theirs = await host.post();
  const { data: mine } = await poster.admin
    .from('activities')
    .insert({
      organizer_id: poster.id,
      category_id: 'games',
      title: 'Paper game night',
      starts_at: new Date(Date.now() + 24 * 60 * 60 * 1000).toISOString(),
      location_name: 'Library',
    })
    .select('id')
    .single();
  const { data: group } = await poster.admin
    .from('groups')
    .insert({
      slug: `paper-${crypto.randomUUID().slice(0, 6)}`,
      name: 'Paper group',
      category_id: 'games',
      description: 'We play board games.',
      owner_id: poster.id,
    })
    .select('id, slug')
    .single();
  await poster.admin
    .from('group_members')
    .insert({ group_id: group!.id, user_id: poster.id, role: 'owner' });

  // On the solid grey (UI-29), with the content on cream paper (UI-26).
  for (const path of [
    `/activities/${theirs}`,
    `/activities/${mine!.id}/update`,
    `/activities/${theirs}/report`,
    `/groups/${group!.slug}`,
    `/groups/${group!.slug}/update`,
    '/groups/new',
    `/people/${host.id}`,
    `/people/${host.id}/report`,
    '/me/edit',
  ]) {
    await page.goto(path);
    await expect(page.locator('main'), path).toHaveCSS('background-color', 'rgb(247, 244, 236)');
    await expect(page.locator('main'), path).toHaveCSS('font-size', '17px');
    await expect(page.locator('html'), path).toHaveCSS('background-color', PAGE);
    expect(await unreadableOnPage(page), path).toEqual([]);
    expect(
      await page.evaluate(() => document.documentElement.scrollWidth <= window.innerWidth),
      path
    ).toBe(true);
  }

  // A group's parts each have a plain heading, all the same size, and Report is in the ⋯ menu.
  await page.goto(`/groups/${group!.slug}`);
  const sizes = new Set<string>();
  for (const name of ['About', 'Category', 'Coming up', 'Members', 'Updates', 'Banner']) {
    const heading = page.getByRole('heading', { name, level: 2, exact: true });
    sizes.add(await heading.evaluate((el) => getComputedStyle(el).fontSize));
  }
  expect(sizes.size).toBe(1);
  await expectAccessible(page);

  // The main tabs don't have it.
  await page.goto('/discover');
  await expect(page.locator('main')).toHaveCSS('background-color', 'rgba(0, 0, 0, 0)');
});

test('text straight on the page is readable', async ({ page, poster, crowd }) => {
  // A group with someone asking to join, so its page has "1 asking to join" near the top.
  const { data: group } = await poster.admin
    .from('groups')
    .insert({
      slug: `readable-${crypto.randomUUID().slice(0, 6)}`,
      name: 'Readable group',
      category_id: 'games',
      join_policy: 'approval',
      owner_id: poster.id,
    })
    .select('id, slug')
    .single();
  await poster.admin
    .from('group_members')
    .insert({ group_id: group!.id, user_id: poster.id, role: 'owner' });
  const [asking] = await crowd(1);
  await asking.rpc('join_group', { group_id: group!.id });

  const found: string[] = [];
  // Back and the page's sentence sit at the top of these.
  for (const path of [
    '/discover',
    '/plans',
    '/notifications',
    '/me',
    '/me/edit',
    '/search',
    '/groups/new',
    `/groups/${group!.slug}`,
    `/people/${poster.id}`,
  ]) {
    await page.goto(path);
    for (const problem of await unreadableOnPage(page)) found.push(`${path}: ${problem}`);
  }
  await page.context().clearCookies();
  for (const path of ['/', '/auth/login']) {
    await page.goto(path);
    for (const problem of await unreadableOnPage(page)) found.push(`${path}: ${problem}`);
  }
  expect(found).toEqual([]);
});

test('each main page says what it is for, in dark text with no shadow, and Me says nothing', async ({
  page,
  signInAs,
}) => {
  await signInAs('member');
  const sentences = {
    '/discover': 'See what your fellow faculty are up to, get involved, and have some fun!',
    '/groups': 'Start a faculty group and get together regularly',
    '/plans': 'Here is what is on your schedule',
    '/notifications': 'Messages that help you keep track of new and changing activities',
  };
  for (const [path, words] of Object.entries(sentences)) {
    await page.goto(path);
    const sentence = page.locator('main .page-sentence');
    await expect(sentence).toHaveText(words);
    // Dark, with no shadow, which made it look blurry (UI-29).
    await expect(sentence).toHaveCSS('color', 'rgb(23, 23, 23)');
    // 1.2em of the page's 16px, which WebKit rounds to 19.200001px.
    await expect(sentence).toHaveCSS('font-size', /^19\.2(0000\d)?px$/);
    await expect(sentence).toHaveCSS('text-shadow', 'none');
    expect(
      await page.evaluate(() => document.documentElement.scrollWidth <= window.innerWidth)
    ).toBe(true);
  }
  // On Groups, Start a group is at its right, on the same line.
  await page.goto('/groups');
  const sentence = await page.locator('main .page-sentence').boundingBox();
  const start = await page
    .locator('main .top')
    .getByRole('link', { name: 'Start a group' })
    .boundingBox();
  expect(start!.x).toBeGreaterThan(sentence!.x + sentence!.width - 1);
  expect(start!.y).toBeLessThan(sentence!.y + sentence!.height);
  await expectAccessible(page);

  await page.goto('/me');
  await expect(page.locator('main .page-sentence')).toHaveCount(0);
});

test("Search is at the right of the header, and Discover's tabs come first", async ({
  page,
  signInAs,
}) => {
  await signInAs('member');
  // Search is at the right of the header's strip on every main tab (UI-19), and Discover's and
  // Groups' tabs come right after the header.
  for (const path of ['/discover', '/plans']) {
    await page.goto(path);
    const header = page.locator('header.site');
    const search = header.getByRole('link', { name: 'Search' });
    const [searchBox, headerBox] = [(await search.boundingBox())!, (await header.boundingBox())!];
    expect(headerBox.x + headerBox.width - (searchBox.x + searchBox.width)).toBeLessThan(16);
    expect(searchBox.height).toBeGreaterThanOrEqual(44);
    // The motto still fits beside the logo and Search, on two lines at most.
    const motto = header.getByText('Bringing faculty together!', { exact: true });
    const lines = await motto.evaluate(
      (el) => el.getBoundingClientRect().height / parseFloat(getComputedStyle(el).lineHeight)
    );
    expect(lines).toBeLessThan(2.5);
  }
  for (const path of ['/discover', '/groups']) {
    await page.goto(path);
    const tabs = (await page.getByRole('navigation', { name: 'Discover' }).boundingBox())!;
    const header = (await page.locator('header.site').boundingBox())!;
    expect(tabs.y - (header.y + header.height)).toBeLessThan(24);
  }
  await page.goto('/search');
  await expect(page.locator('header.site').getByRole('link', { name: 'Search' })).toHaveAttribute(
    'aria-current',
    'page'
  );
});

test('buttons are square, in the display face in capitals, like the tabs', async ({
  page,
  signInAs,
  host,
}) => {
  await signInAs('member');
  // Every kind of button (UI-22): filled, outlined, and links drawn as buttons.
  const square = async (button: Locator) => {
    await expect(button).toHaveCSS('border-top-left-radius', '0px');
    await expect(button).toHaveCSS('border-bottom-right-radius', '0px');
    await expect(button).toHaveCSS('font-family', /^Anton/);
    await expect(button).toHaveCSS('text-transform', 'uppercase');
    expect((await button.boundingBox())!.height).toBeGreaterThanOrEqual(44);
  };
  await page.goto('/me');
  await square(page.getByRole('link', { name: 'Edit profile' }));
  await square(page.getByRole('link', { name: 'See my profile' }));
  // A settings row that's a button stays a row, in plain words.
  await expect(page.getByRole('button', { name: 'Sign out' })).toHaveCSS('text-transform', 'none');
  await page.goto('/groups');
  await square(page.getByRole('link', { name: 'Start a group' }));
  await page.goto('/activities/new');
  await square(page.getByRole('button', { name: 'Post activity' }));
  await square(page.getByRole('link', { name: 'Cancel' }));
  // The capitals come from CSS, so the words stay as written.
  await expect(page.getByRole('button', { name: 'Post activity' })).toHaveText('Post activity');
  // A quiet link that's a button stays quiet words.
  const id = await host.post();
  await page.goto(`/activities/${id}`);
  const quiet = page.getByRole('button', { name: 'Add to calendar' });
  await expect(quiet).not.toHaveCSS('font-family', /^Anton/);
  await expect(quiet).toHaveCSS('text-transform', 'none');
  await expectAccessible(page);
});

// Each element on the page, and its ::before and ::after, with a rounded corner. Faces stay round,
// and so do the browser's own radio buttons and checkboxes.
function roundedCorners(page: Page) {
  return page.evaluate(() => {
    const found: string[] = [];
    for (const element of document.querySelectorAll('*')) {
      if (element.closest('.avatar')) continue;
      for (const pseudo of [null, '::before', '::after']) {
        const style = getComputedStyle(element, pseudo);
        const native =
          element.matches('input[type=radio], input[type=checkbox]') && style.appearance !== 'none';
        const radii = [
          style.borderTopLeftRadius,
          style.borderTopRightRadius,
          style.borderBottomRightRadius,
          style.borderBottomLeftRadius,
        ];
        if (native || radii.every((radius) => radius === '0px')) continue;
        const name = [element.tagName.toLowerCase(), ...element.classList].join('.');
        found.push(`${name}${pseudo ?? ''} is ${radii.join(' ')}`);
      }
    }
    return found;
  });
}

test('everything is square but faces', async ({ page, poster, host, crowd }) => {
  // A group with someone asking to join, and an activity, so the sheet, the unread dot, badges
  // and a toast all turn up.
  const { data: group } = await poster.admin
    .from('groups')
    .insert({
      slug: `square-${crypto.randomUUID().slice(0, 6)}`,
      name: 'Square group',
      category_id: 'games',
      join_policy: 'approval',
      owner_id: poster.id,
    })
    .select('id, slug')
    .single();
  await poster.admin
    .from('group_members')
    .insert({ group_id: group!.id, user_id: poster.id, role: 'owner' });
  const [asking] = await crowd(1);
  await asking.rpc('join_group', { group_id: group!.id });
  const id = await host.post();

  const found: string[] = [];
  for (const path of [
    '/discover',
    '/groups',
    '/plans',
    '/notifications',
    '/me',
    '/me/edit',
    '/search',
    '/activities/new',
    '/groups/new',
    `/groups/${group!.slug}`,
    `/activities/${id}`,
    `/people/${poster.id}`,
  ]) {
    await page.goto(path);
    for (const problem of await roundedCorners(page)) found.push(`${path}: ${problem}`);
  }
  expect(found).toEqual([]);

  // The sheet open, and the toast after approving.
  await page.goto(`/groups/${group!.slug}`);
  await page.getByRole('button', { name: '1 asking to join' }).click();
  const sheet = page.getByRole('dialog', { name: 'Manage members' });
  await expect(sheet).toHaveCSS('border-top-left-radius', '0px');
  await expect(page.locator('.avatar').first()).toHaveCSS('border-top-left-radius', '50%');
  await sheet.getByRole('button', { name: /^Approve/ }).click();
  const toast = page.getByRole('status');
  await expect(toast).toHaveText("Approved. They're in the group.");
  await expect(toast).toHaveCSS('border-top-left-radius', '0px');
  await expect(toast).toHaveCSS('border-bottom-right-radius', '0px');
});

test('in high contrast, the paper gives way to plain borders', async ({ page, poster, host }) => {
  // An unread alert, for its card on Alerts (UI-15).
  const id = await host.post();
  await poster.admin
    .from('notifications')
    .insert({ recipient_id: poster.id, type: 'rsvp_confirmed', activity_id: id, payload: {} });
  await page.emulateMedia({ forcedColors: 'active' });
  await page.goto('/discover');
  const plain = async (piece: Locator) => {
    await expect(piece).toHaveCSS('box-shadow', 'none');
    await expect(piece).not.toHaveCSS('border-left-color', /rgba\(0, 0, 0, 0\)/);
  };
  await plain(
    page.getByRole('navigation', { name: 'Discover' }).getByRole('link', { name: 'Groups' })
  );
  // An activity card's blue column is plain, with a line between it and the rest (UI-17).
  const side = page.getByRole('article').first().locator('.side');
  await expect(side).toHaveCSS('box-shadow', 'none');
  await expect(side).toHaveCSS('border-left-style', 'solid');
  // Nothing behind the page.
  await expect(page.locator('html')).toHaveCSS('background-image', 'none');

  // An alert's card too, and its unread dot still shows.
  await page.goto('/notifications');
  const card = page.getByRole('region', { name: 'New' }).getByRole('button');
  await plain(card);
  await expect(card).toHaveCSS('background-image', 'none');
  const dot = await card.getByText('Sunrise hike up the R').evaluate((el) => {
    const { content, borderTopColor, borderTopWidth } = getComputedStyle(el, '::before');
    return { content, borderTopColor, borderTopWidth };
  });
  expect(dot.content).not.toBe('none');
  expect(dot.borderTopColor).not.toMatch(/rgba\(0, 0, 0, 0\)/);
  expect(parseFloat(dot.borderTopWidth)).toBeGreaterThan(0);

  // New activity's banner, since the main tabs no longer have one (UI-18), and no orange or warm
  // paper behind it (UI-25).
  await page.goto('/activities/new');
  await plain(page.getByRole('heading', { level: 1 }));
  await expect(page.locator('html')).toHaveCSS('background-image', 'none');
  await expect(page.locator('main')).not.toHaveCSS('background-color', WARM_PAPER);
});

test('the motto is beside the logo, on the public pages too', async ({ page }) => {
  for (const path of ['/about', '/guidelines']) {
    await page.goto(path);
    const header = page.locator('header.site');
    const motto = header.getByText('Bringing faculty together!', { exact: true });
    await expect(motto).toBeVisible();
    // To the right of the mark and FABA, and not part of the link, whose name stays FABA.
    const brand = header.getByRole('link', { name: 'FABA', exact: true });
    const [link, words] = [(await brand.boundingBox())!, (await motto.boundingBox())!];
    expect(words.x).toBeGreaterThanOrEqual(link.x + link.width);
    expect(words.x + words.width).toBeLessThanOrEqual(page.viewportSize()!.width);
    // Two lines on a narrow phone are no taller than the logo's link.
    expect(words.height).toBeLessThanOrEqual(link.height);
    expect(
      await page.evaluate(() => document.documentElement.scrollWidth <= window.innerWidth)
    ).toBe(true);
  }
  await expectAccessible(page);
});
