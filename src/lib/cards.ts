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
