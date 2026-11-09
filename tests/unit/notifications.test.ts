import { describe as group, expect, it } from 'vitest';
import { badge, changeLine, describe, TYPES } from '../../src/lib/notifications';

group('describe', () => {
  it('has an icon and a line for each Phase 2 type', () => {
    expect(Object.keys(TYPES)).toEqual([
      'activity_changed',
      'activity_cancelled',
      'activity_restored',
      'organizer_update',
      'rsvp_confirmed',
      'new_attendees',
      'reminder',
      'board_announcement',
    ]);
    expect(describe('activity_cancelled')).toEqual({ icon: '✕', summary: 'Cancelled' });
  });

  it("has a plain line for a type it doesn't know", () => {
    expect(describe('league_score')).toEqual({ icon: '•', summary: 'Update' });
  });
});

group('the Alerts badge', () => {
  it.each([
    [0, ''],
    [1, '1'],
    [9, '9'],
    [10, '9+'],
    [250, '9+'],
  ])('shows %i unread as %j', (count, shown) => {
    expect(badge(count)).toBe(shown);
  });
});

group('changeLine', () => {
  const at = { starts_at: '2026-12-04T19:00:00-07:00', ends_at: null, location_name: 'Library' };

  it.each([
    [
      'a new time the same day',
      { starts_at: '2026-12-04T19:30:00-07:00' },
      'Moved to Fri, Dec 4, 7:30 PM (was 7:00 PM)',
    ],
    [
      'a new day',
      { starts_at: '2026-12-05T19:00:00-07:00' },
      'Moved to Sat, Dec 5, 7:00 PM (was Fri, Dec 4, 7:00 PM)',
    ],
    ['a new end', { ends_at: '2026-12-04T21:30:00-07:00' }, 'Now ends at 9:30 PM'],
    ['a new place', { location_name: 'Hart courts' }, 'Now at Hart courts (was Library)'],
    [
      'a new time and place',
      { starts_at: '2026-12-04T20:00:00-07:00', location_name: 'Hart courts' },
      'Moved to Fri, Dec 4, 8:00 PM (was 7:00 PM). Now at Hart courts (was Library)',
    ],
    ['nothing it can show', {}, ''],
  ])('says %s', (_, change, line) => {
    expect(changeLine(at, { ...at, ...change })).toBe(line);
  });

  it('is the line of an activity_changed notification', () => {
    const payload = { before: at, after: { ...at, location_name: 'Hart courts' } };
    expect(describe('activity_changed', payload).summary).toBe('Now at Hart courts (was Library)');
    expect(describe('activity_changed', {}).summary).toBe('Time or place changed');
  });
});
