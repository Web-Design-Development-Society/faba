import { describe as group, expect, it } from 'vitest';
import { describe, TYPES } from '../../src/lib/notifications';

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
