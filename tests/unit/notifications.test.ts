import { describe as group, expect, it } from 'vitest';
import { badge, changeLine, describe, excerpt, TYPES } from '../../src/lib/notifications';

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

  it('says the details for attendees changed, but not what they are (ACT-09)', () => {
    expect(
      describe('activity_changed', { before: at, after: at, details_changed: true }).summary
    ).toBe('Details for attendees changed');
    const both = {
      before: at,
      after: { ...at, location_name: 'Hart courts' },
      details_changed: true,
    };
    expect(describe('activity_changed', both).summary).toBe(
      'Now at Hart courts (was Library). Details for attendees changed'
    );
  });
});

group('cancelled and back on', () => {
  it.each([
    ['activity_cancelled', { reason: 'Snowed in' }, 'Cancelled: Snowed in'],
    ['activity_cancelled', { reason: null }, 'Cancelled'],
    [
      'activity_restored',
      { starts_at: '2026-12-04T19:00:00-07:00' },
      'Back on for Fri, Dec 4, 7:00 PM',
    ],
    ['activity_restored', {}, 'Back on'],
  ])('says %s with %j as %j', (type, payload, line) => {
    expect(describe(type, payload).summary).toBe(line);
  });
});

group('organizer updates', () => {
  it('says who posted it and what it says', () => {
    const update = { author: 'Dana Smith', body: 'Parking is at the trailhead.' };
    expect(describe('organizer_update', {}, update).summary).toBe(
      'Dana Smith: Parking is at the trailhead.'
    );
    expect(describe('organizer_update', {}, { ...update, author: null }).summary).toBe(
      'The organizer: Parking is at the trailhead.'
    );
  });

  it('says when it was hidden or is gone', () => {
    expect(describe('organizer_update', {}, null).summary).toBe(
      'This update is no longer available'
    );
  });

  it('has its plain line before it has been read', () => {
    expect(describe('organizer_update', {}).summary).toBe('Update from the organizer');
  });
});

group('excerpt', () => {
  it('keeps a short update, on one line', () => {
    expect(excerpt('Bring water.\n\nAnd a headlamp.')).toBe('Bring water. And a headlamp.');
  });

  it('cuts a long one at a word, with an ellipsis', () => {
    const line = excerpt(`${'word '.repeat(40)}end`, 20);
    expect(line).toBe('word word word word…');
    expect(line.length).toBeLessThanOrEqual(20);
  });

  it('cuts one long word where it must', () => {
    expect(excerpt('x'.repeat(30), 10)).toBe(`${'x'.repeat(9)}…`);
  });
});
