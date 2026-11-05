import { describe, expect, it } from 'vitest';
import { nextPage, readCursor } from '../../src/lib/feed';

const last = {
  starts_at: '2026-11-07T14:00:00.123456+00:00',
  id: '3f2b8c1e-5d4a-4b6f-9e2d-7a1c0b9d8e6f',
};

describe('the feed cursor', () => {
  it('reads the cursor of the link it makes', () => {
    const query = nextPage(last);
    expect(query).toBe(
      '?after=2026-11-07T14%3A00%3A00.123456%2B00%3A00&id=3f2b8c1e-5d4a-4b6f-9e2d-7a1c0b9d8e6f'
    );
    expect(readCursor(new URLSearchParams(query))).toEqual({
      after_starts_at: last.starts_at,
      after_id: last.id,
    });
  });

  it('keeps a category, which the cursor leaves out', () => {
    const query = nextPage(last, 'outdoors');
    expect(new URLSearchParams(query).get('cat')).toBe('outdoors');
    expect(readCursor(new URLSearchParams(query))).toEqual({
      after_starts_at: last.starts_at,
      after_id: last.id,
    });
  });

  it.each([
    ['nothing', ''],
    ['no id', '?after=2026-11-07T14%3A00%3A00%2B00%3A00'],
    ['an id that is not a UUID', '?after=2026-11-07T14%3A00%3A00%2B00%3A00&id=1'],
    ['a time without an offset', `?after=2026-11-07T14%3A00%3A00&id=${last.id}`],
    // A + that isn't encoded reads as a space.
    ['a time that is not encoded', `?after=2026-11-07T14:00:00+00:00&id=${last.id}`],
  ])('is the first page for %s', (_, query) => {
    expect(readCursor(new URLSearchParams(query))).toEqual({});
  });
});
