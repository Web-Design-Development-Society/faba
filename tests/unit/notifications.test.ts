import { describe as group, expect, it } from 'vitest';
import {
  badge,
  changeLine,
  describe,
  excerpt,
  PREFERENCE_TYPES,
  TYPES,
} from '../../src/lib/notifications';

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
      'group_join_request',
      'group_update',
      'group_join_approved',
      'group_owner',
      'rsvp_promoted',
      'rsvp_removed',
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

  it('says a change to a series changed its future dates too (REC-02)', () => {
    const moved = { before: at, after: { ...at, location_name: 'Hart courts' }, series: true };
    expect(describe('activity_changed', moved).summary).toBe(
      'Now at Hart courts (was Library). Future dates changed too'
    );
    expect(describe('activity_changed', { before: at, after: at, series: true }).summary).toBe(
      'Time or place changed'
    );
  });
});

group('promoted from the waitlist (RSVP-07)', () => {
  it('says a spot opened, and when', () => {
    const { icon, summary } = describe('rsvp_promoted', { starts_at: '2026-12-05T02:00:00Z' });
    expect(icon).toBe('🎉');
    expect(summary).toMatch(/^A spot opened\. You're going on Fri, Dec 4, 7:00\sPM$/);
    expect(describe('rsvp_promoted', {}).summary).toBe("A spot opened, and you're going");
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

group('RSVP confirmation', () => {
  it.each([
    [{ starts_at: '2026-12-04T19:00:00-07:00' }, "You're going on Fri, Dec 4, 7:00 PM"],
    [{}, "You're going"],
  ])('says %j as %j', (payload, line) => {
    expect(describe('rsvp_confirmed', payload)).toEqual({ icon: '✓', summary: line });
  });
});

group('new attendees', () => {
  it.each([
    [{ count: 1 }, '1 new person is going'],
    [{ count: 3 }, '3 new people are going'],
    [{}, 'New people going'],
  ])('says %j as %j', (payload, line) => {
    expect(describe('new_attendees', payload)).toEqual({ icon: '👋', summary: line });
  });
});

group('reminders', () => {
  const payload = { starts_at: '2026-12-04T12:10:00-07:00', location_name: 'Hart courts' };

  it.each([
    ['the same day', '2026-12-04T07:00:00-07:00', 'Reminder: today at 12:10 PM, Hart courts'],
    ['a later day', '2026-12-05T09:00:00-07:00', 'Reminder: Fri, Dec 4, 12:10 PM, Hart courts'],
  ])('says it on %s', (_, now, line) => {
    expect(describe('reminder', payload, undefined, new Date(now))).toEqual({
      icon: '⏰',
      summary: line,
    });
  });

  it("says just Reminder when it doesn't know when", () => {
    expect(describe('reminder', {}).summary).toBe('Reminder');
  });
});

group('board announcements', () => {
  it.each([
    [{ starts_at: '2026-12-04T19:00:00-07:00' }, 'From the FABA board: Fri, Dec 4, 7:00 PM'],
    [{}, 'From the FABA board'],
  ])('says %j as %j', (payload, line) => {
    expect(describe('board_announcement', payload)).toEqual({ icon: '📣', summary: line });
  });
});

group('join requests', () => {
  it.each([
    [{ name: 'Quilters', member: 'Dana Smith' }, 'Dana Smith asked to join'],
    [{}, 'Asked to join'],
  ])('says %j as %j', (payload, line) => {
    expect(describe('group_join_request', payload)).toEqual({ icon: '🙋', summary: line });
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

  // GRP-04.
  it("says a group's the same way", () => {
    expect(describe('group_update', {}, { author: 'Uma Lee', body: 'Bring boots.' })).toEqual({
      icon: '💬',
      summary: 'Uma Lee: Bring boots.',
    });
    expect(describe('group_update', {}).summary).toBe('Update from the group');
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

group('preferences', () => {
  it('lets a member turn every type off except cancellations', () => {
    expect(PREFERENCE_TYPES).toEqual(
      Object.keys(TYPES).filter((type) => type !== 'activity_cancelled')
    );
    expect(PREFERENCE_TYPES).not.toContain('activity_cancelled');
    expect(PREFERENCE_TYPES).toContain('new_attendees');
  });
});
