import { readFileSync } from 'node:fs';
import { describe, expect, it } from 'vitest';
import { categoryLook } from '../../src/lib/categories';

// The icon names and color tokens of the categories the migration adds.
const migration = readFileSync(
  'supabase/migrations/20261029120200_categories_and_activities.sql',
  'utf8'
);
const seeded = [...migration.matchAll(/\('[a-z-]+', '[^']+', '([a-z-]+)', '([a-z-]+)'/g)].map(
  ([, icon, color_token]) => categoryLook({ icon, color_token })
);

describe('categoryLook', () => {
  it('gives each category in the migration its own icon and color', () => {
    expect(seeded).toHaveLength(10);
    expect(new Set(seeded.map(({ icon }) => icon)).size).toBe(10);
    expect(new Set(seeded.map(({ color }) => color)).size).toBe(10);
  });

  it("falls back to Other's look for names it doesn't know", () => {
    expect(categoryLook({ icon: 'rocket', color_token: 'category-space' })).toEqual(
      categoryLook({ icon: 'sparkle', color_token: 'category-other' })
    );
  });
});
