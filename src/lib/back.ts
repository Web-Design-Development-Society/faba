// Where a member's profile goes back to (PROF-03). An activity's or a group's page opens a profile
// with ?from= its own address, and the profile's Back goes there, named, so a member reading who's
// going doesn't lose the activity. Only those two kinds of page count, so a link can't send Back
// anywhere else. Without one, Back goes to Discover.

/** Where a profile was opened from, if it's an activity's or a group's page. */
export type OpenedFrom =
  { kind: 'activity'; id: string; path: string } | { kind: 'group'; slug: string; path: string };

/** A member's profile, saying the page it was opened from. */
export function profileHref(id: string, from?: string): string {
  return from ? `/people/${id}?from=${encodeURIComponent(from)}` : `/people/${id}`;
}

/** The page in `value` a profile was opened from, when it's an activity's or a group's. */
export function openedFrom(value: string | null): OpenedFrom | null {
  const activity = value?.match(/^\/activities\/([0-9a-f-]{36})$/i);
  if (activity) return { kind: 'activity', id: activity[1], path: activity[0] };
  const group = value?.match(/^\/groups\/([a-z0-9]+(?:-[a-z0-9]+)*)$/);
  if (group) return { kind: 'group', slug: group[1], path: group[0] };
  return null;
}
