// What an activity card reads (ACT-01, design document section 7.5), on Discover and in My
// activities (HIST-02). Members who aren't active have no profile to read, so they're left out of
// the faces. A series' date says how often it repeats (REC-01).
export const CARD = `id, title, starts_at, ends_at, location_name, going_count, guest_total, capacity,
  organizer_id, my_rsvp, hidden_at, time_or_place_changed_at,
  status, is_board_activity, created_at, category:categories(name, icon, color_token),
  series:activity_series(freq),
  going:rsvps(member:profiles!inner(id, display_name, avatar_url, use_initials))`;

/** The most faces on a card. */
export const FACES = 3;

/** True once going and guests have taken every spot (RSVP-04). rsvp() uses the same rule. */
export function isFull(activity: {
  going_count: number;
  guest_total: number;
  capacity: number | null;
}): boolean {
  return (
    activity.capacity !== null && activity.going_count + activity.guest_total >= activity.capacity
  );
}

/** How far back History reaches (HIST-01): 24 months. */
export const HISTORY_MONTHS = 24;

/** The earliest start a History list shows, 24 months before `now`. */
export function historySince(now: Date): string {
  const since = new Date(now);
  since.setMonth(since.getMonth() - HISTORY_MONTHS);
  return since.toISOString();
}

/**
 * The label on a past card for its viewer (HIST-01): "Organized" if they organized it, else "Went"
 * if they were going. Only the viewer sees it, about themselves.
 */
export function historyLabel(activity: {
  organizer_id: string | null;
  my_rsvp: string | null;
  viewer: string;
}): 'Organized' | 'Went' | null {
  if (activity.organizer_id === activity.viewer) return 'Organized';
  return activity.my_rsvp === 'going' ? 'Went' : null;
}
