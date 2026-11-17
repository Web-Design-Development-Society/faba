// Forms made for phones (UI-12). Each project runs at its own width, so this checks every form page
// at 320 px (iPhone SE), 412 px (Pixel 7) and a desktop: fields big enough to tap and read, links
// that stand on their own drawn as buttons, no grey boxes, and nothing scrolling sideways.
import type { Page } from '@playwright/test';
import { expect, expectAccessible, test } from './fixtures';

/** Every visible field is at least 44 px tall with 16 px text, and most of the page's width. */
async function expectPhoneFriendly(page: Page) {
  const problems = await page.evaluate(() => {
    const found: string[] = [];
    // The width of the page's content, which is all the room a field could have.
    const main = document.querySelector('main')!.getBoundingClientRect().width;
    const visible = (el: Element) => {
      const box = el.getBoundingClientRect();
      return box.width > 0 && box.height > 0 && getComputedStyle(el).visibility !== 'hidden';
    };
    const name = (el: Element) => el.id || el.getAttribute('name') || el.outerHTML.slice(0, 60);
    const fields = document.querySelectorAll(
      'main input:not([type="hidden"], [type="checkbox"], [type="radio"], [type="file"]), main textarea, main select'
    );
    for (const field of fields) {
      // Inside a closed panel, such as More options or Date, it isn't on the screen.
      if (!visible(field) || field.closest('details:not([open])')) continue;
      const box = field.getBoundingClientRect();
      const style = getComputedStyle(field);
      if (box.height < 43.5) found.push(`${name(field)} is ${box.height}px tall`);
      if (parseFloat(style.fontSize) < 16) found.push(`${name(field)} has ${style.fontSize} text`);
      // A pair shares the width: the date and time (UI-06), or a date range's From and To (UI-09).
      if (!field.closest('.datetime, .pick') && box.width < main * 0.6) {
        found.push(`${name(field)} is ${Math.round(box.width)}px of ${Math.round(main)}px`);
      }
    }
    for (const link of document.querySelectorAll('main a.button, main summary.button')) {
      if (visible(link) && link.getBoundingClientRect().height < 43.5) {
        found.push(`${link.textContent?.trim()} is too short to tap`);
      }
    }
    // A grey box around a group of choices. A divider above one is fine.
    for (const fieldset of document.querySelectorAll('main fieldset')) {
      if (visible(fieldset) && getComputedStyle(fieldset).borderLeftStyle !== 'none') {
        found.push(`a fieldset has a ${getComputedStyle(fieldset).borderLeftStyle} border`);
      }
    }
    if (document.documentElement.scrollWidth > window.innerWidth)
      found.push('the page scrolls sideways');
    return found;
  });
  expect(problems, `on ${page.url()}`).toEqual([]);
}

test('every form is made for phones', async ({ page, poster, host, crowd }) => {
  test.slow();
  // Pat organizes an activity and owns a group with another member. Hana has an activity and a
  // group Pat can report.
  const { data: mine } = await poster.admin
    .from('activities')
    .insert({
      organizer_id: poster.id,
      category_id: 'games',
      title: 'Board games',
      starts_at: new Date(Date.now() + 24 * 60 * 60 * 1000).toISOString(),
      location_name: 'Library',
    })
    .select('id')
    .single();
  const tag = crypto.randomUUID().slice(0, 6);
  const { data: group } = await poster.admin
    .from('groups')
    .insert({
      slug: `readers-${tag}`,
      name: `Readers ${tag}`,
      category_id: 'learning',
      owner_id: poster.id,
    })
    .select('id, slug')
    .single();
  const [member] = await crowd(1);
  const { data: who } = await member.auth.getUser();
  await poster.admin.from('group_members').insert([
    { group_id: group!.id, user_id: poster.id, role: 'owner', status: 'active' },
    { group_id: group!.id, user_id: who.user!.id, role: 'member', status: 'active' },
  ]);
  const theirs = await host.post();
  const { data: theirGroup } = await host.admin
    .from('groups')
    .insert({
      slug: `hikers-${tag}`,
      name: `Hikers ${tag}`,
      category_id: 'outdoors',
      owner_id: host.id,
    })
    .select('slug')
    .single();

  for (const path of [
    '/activities/new',
    `/activities/${mine!.id}/edit`,
    `/activities/${mine!.id}/update`,
    `/activities/${mine!.id}`,
    `/activities/${theirs}/report`,
    '/groups/new',
    `/groups/${group!.slug}`,
    `/groups/${group!.slug}/update`,
    `/groups/${group!.slug}/owner`,
    `/groups/${theirGroup!.slug}/report`,
    `/people/${host.id}/report`,
    '/me',
    '/me/edit',
    '/me/delete',
    '/me/notifications',
    '/search?q=hike',
  ]) {
    await page.goto(path);
    await expectPhoneFriendly(page);
    await expectAccessible(page);
  }
});

test('a form ends with Cancel beside its main action, and links on their own are buttons', async ({
  page,
  poster,
}) => {
  expect(poster.id).toBeTruthy();
  await page.goto('/groups/new');
  const cancel = page.getByRole('link', { name: 'Cancel' });
  const start = page.getByRole('button', { name: 'Start group' });
  await expect(cancel).toHaveAttribute('href', '/groups');
  const [a, b] = [(await cancel.boundingBox())!, (await start.boundingBox())!];
  // Side by side, the main action the wider, and both as tall as a field.
  expect(Math.abs(a.y - b.y)).toBeLessThanOrEqual(1);
  expect(b.width).toBeGreaterThan(a.width);
  expect(a.height).toBeGreaterThanOrEqual(44);
  // The categories are chips, not a list of radio buttons.
  await page.locator('label', { hasText: 'Games' }).click();
  await expect(page.getByRole('radio', { name: 'Games' })).toBeChecked();
  await expect(page.locator('label', { hasText: 'Games' })).toHaveCSS(
    'background-color',
    'rgb(11, 91, 211)'
  );

  // A link on its own looks like a button, and is still a link.
  await page.goto('/me');
  await expect(page.getByRole('link', { name: 'See my profile' })).toHaveCSS(
    'border-top-style',
    'solid'
  );
  await expect(page.getByRole('link', { name: 'Delete account' })).toHaveCSS(
    'color',
    'rgb(180, 35, 24)'
  );
});
