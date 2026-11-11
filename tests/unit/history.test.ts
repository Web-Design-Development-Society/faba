import { describe, expect, it } from 'vitest';
import { historyLabel, historySince, HISTORY_MONTHS } from '../../src/lib/cards';

describe('historyLabel', () => {
  const viewer = 'member-1';

  it('says Organized when the viewer organized it, even if they were going too', () => {
    expect(historyLabel({ organizer_id: viewer, my_rsvp: 'going', viewer })).toBe('Organized');
    expect(historyLabel({ organizer_id: viewer, my_rsvp: null, viewer })).toBe('Organized');
  });

  it('says Went when the viewer was going and didn’t organize it', () => {
    expect(historyLabel({ organizer_id: 'other', my_rsvp: 'going', viewer })).toBe('Went');
  });

  it('has no label for anything else', () => {
    expect(historyLabel({ organizer_id: 'other', my_rsvp: 'maybe', viewer })).toBeNull();
    expect(historyLabel({ organizer_id: 'other', my_rsvp: null, viewer })).toBeNull();
    expect(historyLabel({ organizer_id: 'other', my_rsvp: 'waitlisted', viewer })).toBeNull();
  });
});

describe('historySince', () => {
  it('reaches back 24 months from now', () => {
    expect(HISTORY_MONTHS).toBe(24);
    const now = new Date('2026-11-10T12:00:00Z');
    expect(historySince(now)).toBe('2024-11-10T12:00:00.000Z');
  });
});
