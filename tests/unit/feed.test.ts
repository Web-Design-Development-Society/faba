import { describe, expect, it } from 'vitest';
import { nextPage, readCursor, readDates } from '../../src/lib/feed';

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

describe('the date filter', () => {
  // Wednesday, November 11, 2026, at 3 PM in Rexburg
  const now = new Date('2026-11-11T22:00:00Z');
  const read = (query: string) => readDates(new URLSearchParams(query), now);

  it('reads a chip', () => {
    expect(read('?when=weekend')).toEqual({
      when: 'weekend',
      starts_from: '2026-11-14T00:00:00.000Z',
      starts_before: '2026-11-16T07:00:00.000Z',
    });
  });

  it('reads dates, which win over a chip', () => {
    expect(read('?when=today&from=2026-11-20&to=2026-11-21')).toEqual({
      from: '2026-11-20',
      to: '2026-11-21',
      starts_from: '2026-11-20T07:00:00.000Z',
      starts_before: '2026-11-22T07:00:00.000Z',
    });
  });

  it('reads one date without the other', () => {
    expect(read('?to=2026-11-21')).toEqual({
      to: '2026-11-21',
      starts_from: undefined,
      starts_before: '2026-11-22T07:00:00.000Z',
    });
  });

  it.each([
    ['nothing', ''],
    ['an unknown chip', '?when=someday'],
    ['a date that is not one', '?from=2026-11-31'],
    ['dates the wrong way round', '?from=2026-11-21&to=2026-11-20'],
    ['empty dates', '?from=&to='],
  ])('has no filter for %s', (_, query) => {
    expect(read(query)).toEqual({});
  });
});
