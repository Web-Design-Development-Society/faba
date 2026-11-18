// Where a member's profile goes back to (PROF-03): only an activity's or a group's page.
import { describe, expect, it } from 'vitest';
import { openedFrom, profileHref } from '../../src/lib/back';

const ID = '3f2a9c4e-1b7d-4e8a-9c3f-5d6e7f8a9b0c';

describe('profileHref', () => {
  it('says the page it was opened from', () => {
    expect(profileHref('p1', `/activities/${ID}`)).toBe(`/people/p1?from=%2Factivities%2F${ID}`);
  });

  it('is just the profile without one', () => {
    expect(profileHref('p1')).toBe('/people/p1');
  });
});

describe('openedFrom', () => {
  it("knows an activity's page and a group's page", () => {
    expect(openedFrom(`/activities/${ID}`)).toEqual({
      kind: 'activity',
      id: ID,
      path: `/activities/${ID}`,
    });
    expect(openedFrom('/groups/trail-runners-a1b2')).toEqual({
      kind: 'group',
      slug: 'trail-runners-a1b2',
      path: '/groups/trail-runners-a1b2',
    });
  });

  it('refuses anywhere else, so a link cannot send Back off the site or somewhere odd', () => {
    for (const value of [
      null,
      '',
      'https://example.com',
      '//example.com',
      `https://example.com/activities/${ID}`,
      'javascript:alert(1)',
      '/activities/not-an-id',
      `/activities/${ID}/edit`,
      `/activities/${ID}?x=1`,
      '/groups/Trail_Runners',
      '/groups/-runners',
      '/groups/runners/update',
      '/discover',
    ]) {
      expect(openedFrom(value), String(value)).toBeNull();
    }
  });
});
