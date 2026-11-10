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

/** An organizer update, as the center reads it by the id in its notification (NOTIF-04). */
export type PostedUpdate = { author: string | null; body: string };

/** The most of an update's text the center shows. */
export const EXCERPT_MAX = 120;

/** `text` on one line, cut at a word to at most `max` characters with an ellipsis. */
export function excerpt(text: string, max = EXCERPT_MAX): string {
  const line = text.replace(/\s+/g, ' ').trim();
  if (line.length <= max) return line;
  // A space right after the cut still ends a whole word.
  const space = line.lastIndexOf(' ', max - 1);
  return `${(space > max / 2 ? line.slice(0, space) : line.slice(0, max - 1)).trimEnd()}…`;
}

/**
 * The center's line for a notification of `type`, and its icon, using its payload if it can. For
 * organizer_update, `update` is the update it names, or null when it can't be read because a
 * moderator hid it or it's gone.
 */
export function describe(
  type: string,
  payload?: unknown,
  update?: PostedUpdate | null
): { icon: string; summary: string } {
  const found = TYPES[type] ?? { icon: '•', summary: 'Update' };
  const { before, after, count, details_changed, reason, starts_at } = (payload ?? {}) as {
    before?: Snapshot;
    after?: Snapshot;
    count?: number;
    details_changed?: boolean;
    reason?: string | null;
    starts_at?: string;
  };
  const summary = (() => {
    switch (type) {
      // NOTIF-02, with ACT-09's details for attendees, which it says changed without saying what
      // they are.
      case 'activity_changed':
        return [
          before && after ? changeLine(before, after) : '',
          details_changed ? 'Details for attendees changed' : '',
        ]
          .filter(Boolean)
          .join('. ');
      // NOTIF-03: "Cancelled: Snowed in", and "Back on for Fri, Dec 4, 7:00 PM".
      case 'activity_cancelled':
        return reason ? `Cancelled: ${reason}` : '';
      case 'activity_restored':
        return starts_at ? `Back on for ${formatWhen(new Date(starts_at))}` : '';
      // NOTIF-04: "Dana Smith: Parking is at the trailhead…".
      case 'organizer_update':
        if (update === undefined) return '';
        return update
          ? `${update.author ?? 'The organizer'}: ${excerpt(update.body)}`
          : 'This update is no longer available';
      // NOTIF-05: "You're going on Fri, Dec 4, 7:00 PM".
      case 'rsvp_confirmed':
        return starts_at ? `You're going on ${formatWhen(new Date(starts_at))}` : '';
      // NOTIF-06: "3 new people are going", for the organizer.
      case 'new_attendees':
        if (typeof count !== 'number' || count < 1) return '';
        return count === 1 ? '1 new person is going' : `${count} new people are going`;
      default:
        return '';
    }
  })();
  return summary ? { ...found, summary } : found;
}

/** The Alerts badge for `count` unread notifications, which stops at "9+", or nothing for none. */
export function badge(count: number): string {
  return count > 9 ? '9+' : count > 0 ? String(count) : '';
}
