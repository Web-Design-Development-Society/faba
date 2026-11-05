// What an activity card reads (ACT-01, design document section 7.5), on Discover and in My
// activities (HIST-02). Members who aren't active have no profile to read, so they're left out of
// the faces.
export const CARD = `id, title, starts_at, ends_at, location_name, going_count, organizer_id, my_rsvp,
  status, category:categories(name, icon, color_token),
  going:rsvps(member:profiles!inner(id, display_name, avatar_url, use_initials))`;

/** The most faces on a card. */
export const FACES = 3;
