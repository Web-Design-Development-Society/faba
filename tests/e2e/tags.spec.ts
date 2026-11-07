// Tagging an activity (SRCH-03). The pgTAP tests cover the rules.
import { expect, expectAccessible, test } from './fixtures';

test('an organizer tags an activity, and changes its tags', async ({ page, poster }) => {
  await page.goto('/activities/new');
  await page.getByLabel('What are you doing?').fill('Picnic in the park');
  await page.getByLabel('Start time').fill('12:00');
  await page.getByRole('button', { name: 'Tomorrow' }).click();
  await page.getByLabel('Where?').fill('Porter Park');
  await page.getByRole('radio', { name: 'Food & Socials' }).check();
  await page.getByText('More options').click();
  const tags = page.getByRole('group', { name: 'Tags' });
  await tags.getByLabel('Free').check();
  await tags.getByLabel('Family-friendly').check();
  await expectAccessible(page);
  await page.getByRole('button', { name: 'Post activity' }).click();
  await expect(page.getByText('Free · Family-friendly')).toBeVisible();

  await page.getByRole('link', { name: 'Edit' }).click();
  await expect(tags.getByLabel('Free')).toBeChecked();
  await tags.getByLabel('Free').uncheck();
  await page.getByRole('button', { name: 'Save' }).click();
  await expect(page.getByText('Family-friendly', { exact: true })).toBeVisible();

  const { data } = await poster.admin
    .from('activity_tags')
    .select('tag_id, activities!inner(organizer_id)')
    .eq('activities.organizer_id', poster.id);
  expect(data?.map(({ tag_id }) => tag_id)).toEqual(['family-friendly']);
});
