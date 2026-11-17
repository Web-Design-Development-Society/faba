// FABA's look (UI-02, UI-14, UI-16, UI-18): the bottom bar keeps its five items, each with a line
// icon in a tile over its label, and the current tab and chosen date are FABA blue. The cut-paper
// look puts headings in Anton, in capitals by CSS, and each tab on a piece of paper with a shadow,
// on a gradient that text sits straight on, readable all the way down. Every corner is square but
// faces. The main tabs' headings are for screen readers only, since the bottom bar shows which
// page it is.
import type { Locator, Page } from '@playwright/test';
import { expect, expectAccessible, expectSquare, paper, test } from './fixtures';

const BLUE = 'rgb(11, 91, 211)';
const SKY = 'rgb(207, 225, 250)';
const NAVY = 'rgb(15, 31, 61)';

test('selected things are FABA blue, and the bar keeps its five items', async ({
  page,
  signInAs,
}) => {
  await signInAs('member');
  await page.goto('/discover');

  const bar = page.getByRole('navigation', { name: 'Main' });
  await expect(bar.getByRole('link')).toHaveText(['Discover', 'Plans', 'Post', /^Alerts/, 'Me']);
  await expect(bar.locator('svg')).toHaveCount(5);
  // The current tab's tile is light blue, and it's underlined, so it isn't color alone.
  const here = bar.getByRole('link', { name: 'Discover' });
  await expect(here).toHaveAttribute('aria-current', 'page');
  await expect(here.locator('.tile')).toHaveCSS('background-color', SKY);
  await expect(bar.getByRole('link', { name: 'Plans' }).locator('.tile')).toHaveCSS(
    'background-color',
    'rgb(255, 255, 255)'
  );
  // Post is a navy square that rises above the bar (UI-14).
  await expect(bar.locator('.post .square')).toHaveCSS('background-color', NAVY);

  // Activities is on FABA blue paper, and Groups on light blue.
  const halves = page.getByRole('navigation', { name: 'Discover' });
  expect(await paper(halves.getByRole('link', { name: 'Activities' }))).toBe('0b5bd3');
  expect(await paper(halves.getByRole('link', { name: 'Groups' }))).toBe('cfe1fa');
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

test("the main tabs' headings are for screen readers, and New activity keeps its banner", async ({
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
    // Even a short page, such as Alerts with none, is as tall as the screen, so the background's
    // gradient ends at its bottom instead of starting again.
    expect(
      await page.evaluate(
        () => document.documentElement.getBoundingClientRect().height >= window.innerHeight
      )
    ).toBe(true);
  }
  // New activity keeps its banner: big, in Anton and in capitals.
  await page.goto('/activities/new');
  const heading = page.getByRole('heading', { level: 1 });
  // Capitals come from CSS, so the page, screen readers and search keep the words as written.
  await expect(heading).toHaveText('New activity');
  await expect(heading).toHaveCSS('text-transform', 'uppercase');
  await expect(heading).toHaveCSS('font-family', /^Anton/);
  expect(await page.evaluate(() => document.fonts.check('48px Anton'))).toBe(true);
  // On one line at every width, and as big as a heading on a phone should be.
  const size = parseFloat(await heading.evaluate((el) => getComputedStyle(el).fontSize));
  expect(size).toBeGreaterThanOrEqual(36);
  expect((await heading.boundingBox())!.height).toBeLessThan(size * 1.6);
  // It sits on its own strip of white paper, with square corners and a shadow (UI-16). The page's
  // content has no sheet: it sits straight on a soft gradient, with no photo behind it.
  expect(await paper(heading)).toBe('ffffff');
  await expectSquare(heading);
  const main = page.locator('main');
  await expect(main).toHaveCSS('background-color', 'rgba(0, 0, 0, 0)');
  await expect(main).toHaveCSS('box-shadow', 'none');
  // The logo's light blue at the top, light blue paper, then cream at the bottom, and it doesn't
  // repeat.
  const html = page.locator('html');
  await expect(html).toHaveCSS(
    'background-image',
    'linear-gradient(rgb(63, 164, 250), rgb(207, 225, 250), rgb(247, 244, 236))'
  );
  await expect(html).toHaveCSS('background-repeat', 'no-repeat');
  expect(
    await page.evaluate(() => getComputedStyle(document.documentElement, '::before').content)
  ).toBe('none');
  expect(await page.evaluate(() => document.documentElement.scrollWidth <= window.innerWidth)).toBe(
    true
  );
  await expectAccessible(page);
});

/**
 * The text that sits straight on the page's gradient, with nothing behind it but the page, and
 * whose contrast with the gradient where it sits is under WCAG's 4.5:1, or 3:1 for large text. axe
 * can't measure text on a gradient, so this finds the gradient's color at the middle of each. Each
 * main page's sentence (UI-24) is white with a shadow, an agreed exception, so it's left out.
 */
async function unreadableOnGradient(page: Page) {
  return page.evaluate(() => {
    const rgb = (value: string) => (value.match(/[\d.]+/g) ?? []).map(Number);
    const luminance = ([r, g, b]: number[]) => {
      const linear = (c: number) =>
        (c /= 255) <= 0.03928 ? c / 12.92 : ((c + 0.055) / 1.055) ** 2.4;
      return 0.2126 * linear(r) + 0.7152 * linear(g) + 0.0722 * linear(b);
    };
    const contrast = (a: number[], b: number[]) => {
      const [light, dark] = [luminance(a), luminance(b)].sort((x, y) => y - x);
      return (light + 0.05) / (dark + 0.05);
    };
    const html = document.documentElement;
    const stops = (getComputedStyle(html).backgroundImage.match(/rgb\([^)]*\)/g) ?? []).map(rgb);
    const height = html.getBoundingClientRect().height;
    // The stops are evenly spaced from the top of the page to its bottom.
    const behind = (y: number) => {
      const at = Math.min(Math.max(y / height, 0), 1) * (stops.length - 1);
      const i = Math.min(Math.floor(at), stops.length - 2);
      return stops[i].map((c, k) => c + (stops[i + 1][k] - c) * (at - i));
    };
    const onGradient = (element: Element) => {
      for (let e: Element | null = element; e && e !== html; e = e.parentElement) {
        const style = getComputedStyle(e);
        if (style.backgroundImage !== 'none' || rgb(style.backgroundColor)[3] !== 0) return false;
      }
      return true;
    };
    const found: string[] = [];
    for (const element of document.body.querySelectorAll('*')) {
      const text = [...element.childNodes]
        .filter((node) => node.nodeType === Node.TEXT_NODE)
        .map((node) => node.textContent!.trim())
        .join(' ')
        .trim();
      const box = element.getBoundingClientRect();
      const style = getComputedStyle(element);
      if (!text || box.width <= 1 || box.height <= 1 || style.visibility === 'hidden') continue;
      if (!onGradient(element) || element.closest('.page-sentence')) continue;
      const size = parseFloat(style.fontSize);
      const large = size >= 24 || (size >= 18.66 && Number(style.fontWeight) >= 700);
      const ratio = contrast(rgb(style.color), behind(box.top + scrollY + box.height / 2));
      if (ratio < (large ? 3 : 4.5)) found.push(`"${text.slice(0, 40)}" is ${ratio.toFixed(1)}:1`);
    }
    return found;
  });
}

test('text straight on the gradient is readable, even at its bluest', async ({
  page,
  poster,
  crowd,
}) => {
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
  // Back sits at the top of each of these, where the gradient is bluest.
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
    for (const problem of await unreadableOnGradient(page)) found.push(`${path}: ${problem}`);
  }
  await page.context().clearCookies();
  for (const path of ['/', '/auth/login']) {
    await page.goto(path);
    for (const problem of await unreadableOnGradient(page)) found.push(`${path}: ${problem}`);
  }
  expect(found).toEqual([]);
});

test('each main page says what it is for, in white with a shadow, and Me says nothing', async ({
  page,
  signInAs,
}) => {
  await signInAs('member');
  const sentences = {
    '/discover': 'See what your fellow faculty are up to, get involved, and have some fun!',
    '/groups': 'Start a faculty group and get together regularly',
    '/plans': 'Here is what is on my schedule',
    '/notifications': 'Messages that help you keep track of new and changing activities',
  };
  for (const [path, words] of Object.entries(sentences)) {
    await page.goto(path);
    const sentence = page.locator('main .page-sentence');
    await expect(sentence).toHaveText(words);
    await expect(sentence).toHaveCSS('color', 'rgb(255, 255, 255)');
    // 1.2em of the page's 16px.
    await expect(sentence).toHaveCSS('font-size', '19.2px');
    await expect(sentence).toHaveCSS('text-shadow', 'rgb(10, 79, 184) 1px 2px 0px');
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

  // New activity's banner, since the main tabs no longer have one (UI-18).
  await page.goto('/activities/new');
  await plain(page.getByRole('heading', { level: 1 }));
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
