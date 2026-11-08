// Notifications (NOTIF-01, design document sections 7.3, 7.9 and 8.8): the Alerts badge, and the
// notification center's words. A notification stores data, and this writes the words. The stories
// that make each type can make its line more specific from the payload, such as NOTIF-02's old and
// new times.

/** Each type's icon and one-line summary, for the Phase 2 types in section 8.8. */
export const TYPES: Record<string, { icon: string; summary: string }> = {
  activity_changed: { icon: '🕒', summary: 'Time or place changed' },
  activity_cancelled: { icon: '✕', summary: 'Cancelled' },
  activity_restored: { icon: '↺', summary: 'Back on' },
  organizer_update: { icon: '💬', summary: 'Update from the organizer' },
  rsvp_confirmed: { icon: '✓', summary: "You're going" },
  new_attendees: { icon: '👋', summary: 'New people going' },
  reminder: { icon: '⏰', summary: 'Reminder' },
  board_announcement: { icon: '📣', summary: 'From the FABA board' },
};

/** The center's line for a notification of `type`, and its icon. */
export function describe(type: string): { icon: string; summary: string } {
  return TYPES[type] ?? { icon: '•', summary: 'Update' };
}

/** The Alerts badge for `count` unread notifications, which stops at "9+", or nothing for none. */
export function badge(count: number): string {
  return count > 9 ? '9+' : count > 0 ? String(count) : '';
}
