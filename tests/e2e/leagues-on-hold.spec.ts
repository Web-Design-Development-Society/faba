// Leagues are on hold (ADR-018): FABA has basic groups, and nothing leads to a league. Their code
// stays, so this runs only while src/lib/features.ts has them off.
import { LEAGUES } from '../../src/lib/features';
import { expect, test } from './fixtures';

test.skip(LEAGUES, 'Leagues are on.');

test('nothing leads to a league, and its pages and Actions are not found', async ({
  page,
  poster,
}) => {
  const name = `Pickleball ${crypto.randomUUID().slice(0, 6)}`;
  const { data: league } = await poster.admin
    .from('groups')
    .insert({
      slug: name.toLowerCase().replace(/[^a-z0-9]+/g, '-'),
      name,
      category_id: 'sports',
      kind: 'league',
      owner_id: poster.id,
    })
    .select('id, slug')
    .single();
  await poster.admin
    .from('group_members')
    .insert({ group_id: league!.id, user_id: poster.id, role: 'owner', status: 'active' });

  await page.goto('/groups');
  await expect(page.getByRole('link', { name: 'Start a group' })).toBeVisible();
  await expect(page.getByRole('link', { name: 'Start a league' })).toHaveCount(0);
  // A league made before is just a group, with no League badge and no Seasons.
  const card = page.getByRole('article').filter({ hasText: name });
  await expect(card.getByText('League', { exact: true })).toHaveCount(0);
  await page.goto(`/groups/${league!.slug}`);
  await expect(page.getByRole('heading', { level: 1 })).toHaveText(name);
  await expect(page.getByRole('link', { name: 'Seasons' })).toHaveCount(0);

  expect((await page.request.get('/leagues/new')).status()).toBe(404);
  expect((await page.request.get(`/groups/${league!.slug}/seasons`)).status()).toBe(404);
  const started = await page.request.post('/_actions/leagues.create', {
    form: { name: 'Sneaky league', category_id: 'sports', join_policy: 'open' },
  });
  expect(started.status()).toBe(404);

  // Me → Notifications doesn't offer a league's sub requests.
  await page.goto('/me/notifications');
  await expect(page.getByText('A sub is needed')).toHaveCount(0);
});
