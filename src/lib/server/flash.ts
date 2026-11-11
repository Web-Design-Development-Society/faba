// One-time messages for the page after a redirect, such as "Posted!" (ACT-03). A short-lived
// cookie carries them, so they work without JavaScript and don't stay in the URL to be shared.
import type { AstroCookies } from 'astro';
import { authCookieOptions } from './auth';

export const FLASH_MESSAGES = {
  posted: 'Posted!',
  saved: 'Saved.',
  saved_series: 'Saved for this and future dates.',
  cancelled: 'Cancelled.',
  restored: "Restored. It's back on.",
  going: "You're going.",
  maybe: "You're a maybe.",
  not_going: "You're not going.",
  waitlisted: "You're on the waitlist.",
  joined_series: "You're in for all upcoming dates.",
  left_series: 'You left the series.',
  co_organizer_added: 'Co-organizer added.',
  co_organizer_removed: 'Co-organizer removed.',
  attendee_removed: 'Taken off the list.',
  reported: 'Thanks, a moderator will review this.',
  dismissed: 'Report dismissed.',
  hidden: 'Activity hidden.',
  unhidden: 'Activity unhidden.',
  suspended: 'Member suspended.',
  reinstated: 'Member reinstated.',
  transferred: 'New host set.',
  read: 'All caught up.',
  muted: "Muted. You'll still hear if it's cancelled.",
  unmuted: 'Unmuted.',
  update_posted: 'Update posted.',
  update_hidden: 'Update hidden.',
  update_unhidden: 'Update unhidden.',
  board: 'Marked as a board activity.',
  not_board: 'No longer a board activity.',
  announced: 'Announced to every member.',
  group_started: 'Group started!',
  joined: "You're in the group.",
  requested: "Request sent. You're in once an organizer approves it.",
  left: 'You left the group.',
  withdrawn: 'Request withdrawn.',
  approved: "Approved. They're in the group.",
  declined: 'Request declined.',
  removed: 'Removed from the group.',
  made_organizer: "They're an organizer now.",
  made_member: "They're a member now.",
  group_handed_on: 'New owner set.',
};

export type Flash = keyof typeof FLASH_MESSAGES;

const FLASH_COOKIE = 'faba-flash';

export function setFlash(cookies: AstroCookies, url: URL, flash: Flash) {
  cookies.set(FLASH_COOKIE, flash, { ...authCookieOptions(url), maxAge: 60 });
}

/** The message waiting for this page, if any. Taking it clears it. */
export function takeFlash(cookies: AstroCookies): Flash | undefined {
  const flash = cookies.get(FLASH_COOKIE)?.value;
  if (!flash) return undefined;
  cookies.delete(FLASH_COOKIE, { path: '/' });
  return Object.hasOwn(FLASH_MESSAGES, flash) ? (flash as Flash) : undefined;
}

/**
 * Where to redirect after a form posts to an Action on its own page: the same page without the
 * Action, which Astro names in `_action`, and with `hash`, such as a card's id.
 */
export function postedFrom(url: URL, hash = ''): string {
  const back = new URL(url);
  back.searchParams.delete('_action');
  return back.pathname + back.search + hash;
}
