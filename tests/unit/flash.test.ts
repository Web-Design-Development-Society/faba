import { describe, expect, it } from 'vitest';
import { postedFrom } from '../../src/lib/server/flash';

describe('postedFrom', () => {
  it.each([
    ['/activities/a1?_action=rsvps.set', '', '/activities/a1'],
    [
      '/discover?after=2026-11-07T14%3A00%3A00Z&id=a1&_action=rsvps.set',
      '',
      '/discover?after=2026-11-07T14%3A00%3A00Z&id=a1',
    ],
    ['/discover?_action=rsvps.set', '#activity-a1', '/discover#activity-a1'],
  ])('%s with hash %j comes back to %s', (posted, hash, back) => {
    expect(postedFrom(new URL(posted, 'https://faba.test'), hash)).toBe(back);
  });
});
