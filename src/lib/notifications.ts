// Notifications (NOTIF-01, design document sections 7.3, 7.9 and 8.8): the Alerts badge, and the
// notification center's words. A notification stores data, and this writes the words. The stories
// that make each type can make its line more specific from the payload, such as NOTIF-02's old and
// new times.
import { formatClock, formatWhen, rexburgDate } from './time';

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

/** An activity's time and place, as an activity_changed payload has them before and after. */
type Snapshot = { starts_at?: string; ends_at?: string | null; location_name?: string };

/**
 * What changed, from `before` to `after` (NOTIF-02), such as "Moved to Fri, Dec 4, 7:30 PM (was
 * 7:00 PM)" or "Now at Hart courts (was Library)". The old time leaves out its date when it's the
 * same day. Without a change it can show, it's nothing.
 */
export function changeLine(before: Snapshot, after: Snapshot): string {
  const lines: string[] = [];
  if (before.starts_at && after.starts_at && before.starts_at !== after.starts_at) {
    const now = new Date(after.starts_at);
    const was = new Date(before.starts_at);
    const sameDay = rexburgDate(now) === rexburgDate(was);
    lines.push(`Moved to ${formatWhen(now)} (was ${sameDay ? formatClock(was) : formatWhen(was)})`);
  } else if (after.ends_at && before.ends_at !== after.ends_at) {
    lines.push(`Now ends at ${formatClock(new Date(after.ends_at))}`);
  }
  if (before.location_name && after.location_name && before.location_name !== after.location_name) {
    lines.push(`Now at ${after.location_name} (was ${before.location_name})`);
  }
  return lines.join('. ');
}

/** The center's line for a notification of `type`, and its icon, using its payload if it can. */
export function describe(type: string, payload?: unknown): { icon: string; summary: string } {
  const found = TYPES[type] ?? { icon: '•', summary: 'Update' };
  const { before, after, reason, starts_at } = (payload ?? {}) as {
    before?: Snapshot;
    after?: Snapshot;
    reason?: string | null;
    starts_at?: string;
  };
  // NOTIF-03: "Cancelled: Snowed in", and "Back on for Fri, Dec 4, 7:00 PM".
  const summary =
    type === 'activity_changed' && before && after
      ? changeLine(before, after)
      : type === 'activity_cancelled' && reason
        ? `Cancelled: ${reason}`
        : type === 'activity_restored' && starts_at
          ? `Back on for ${formatWhen(new Date(starts_at))}`
          : '';
  return summary ? { ...found, summary } : found;
}

/** The Alerts badge for `count` unread notifications, which stops at "9+", or nothing for none. */
export function badge(count: number): string {
  return count > 9 ? '9+' : count > 0 ? String(count) : '';
}
