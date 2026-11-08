// Dates and times in Rexburg (ADR-017). Every activity is in America/Denver, whatever time zone
// the server or the browser is in, so these work the same in both.

export const TIME_ZONE = 'America/Denver';

const parts = new Intl.DateTimeFormat('en-US', {
  timeZone: TIME_ZONE,
  hourCycle: 'h23',
  year: 'numeric',
  month: '2-digit',
  day: '2-digit',
  hour: '2-digit',
  minute: '2-digit',
  second: '2-digit',
});

/** Rexburg's wall clock at `instant`, as if it were UTC. */
function wallClock(instant: Date): number {
  const p = Object.fromEntries(
    parts.formatToParts(instant).map(({ type, value }) => [type, value])
  );
  return Date.UTC(+p.year, +p.month - 1, +p.day, +p.hour, +p.minute, +p.second);
}

/** The date in Rexburg at `instant`, such as `2026-11-07`. */
export function rexburgDate(instant: Date): string {
  return new Date(wallClock(instant)).toISOString().slice(0, 10);
}

/** `date` moved by `days`, such as `2026-11-08` for `2026-11-07` and 1. */
export function addDays(date: string, days: number): string {
  const [year, month, day] = date.split('-').map(Number);
  return new Date(Date.UTC(year, month - 1, day + days)).toISOString().slice(0, 10);
}

/** The create form's quick date picks for `now` in Rexburg. On a Saturday, this Saturday is today. */
export function quickDates(now: Date) {
  const today = rexburgDate(now);
  const weekday = new Date(`${today}T00:00:00Z`).getUTCDay();
  return { today, tomorrow: addDays(today, 1), saturday: addDays(today, (6 - weekday) % 7) };
}

/** The time in Rexburg at `instant`, such as `07:00`. */
export function rexburgTime(instant: Date): string {
  return new Date(wallClock(instant)).toISOString().slice(11, 16);
}

const when = new Intl.DateTimeFormat('en-US', {
  weekday: 'short',
  month: 'short',
  day: 'numeric',
  hour: 'numeric',
  minute: '2-digit',
  timeZone: TIME_ZONE,
});

/** A date and time for people, such as `Sat, Nov 7, 7:00 AM`. */
export function formatWhen(instant: Date): string {
  return when.format(instant);
}

/**
 * From `start` to `end` for people, such as `Sat, Nov 7, 7:00 – 9:30 AM`. The end's date shows
 * only when it's another day. Without an end, it's the start.
 */
export function formatRange(start: Date, end?: Date | null): string {
  return end ? when.formatRange(start, end) : when.format(start);
}

const NEARBY: Record<number, string> = { [-1]: 'Yesterday', 0: 'Today', 1: 'Tomorrow' };

const clock = new Intl.DateTimeFormat('en-US', {
  hour: 'numeric',
  minute: '2-digit',
  timeZone: TIME_ZONE,
});
const weekday = new Intl.DateTimeFormat('en-US', { weekday: 'short', timeZone: TIME_ZONE });
const monthDay = new Intl.DateTimeFormat('en-US', {
  month: 'short',
  day: 'numeric',
  timeZone: TIME_ZONE,
});
// Dates such as `2026-11-07` are read as noon UTC, which is the same date everywhere it's formatted.
const day = new Intl.DateTimeFormat('en-US', {
  weekday: 'short',
  month: 'short',
  day: 'numeric',
  timeZone: 'UTC',
});

/** Days from Rexburg's date at `now` to `date`. */
function daysFrom(now: Date, date: string): number {
  return (Date.parse(date) - Date.parse(rexburgDate(now))) / 86_400_000;
}

/** A day's heading in the feed, such as `Today`, `Tomorrow` or `Sat, Nov 7`. */
export function formatDay(date: string, now: Date): string {
  return NEARBY[daysFrom(now, date)] ?? day.format(new Date(`${date}T12:00:00Z`));
}

/** The time in Rexburg for people, such as `7:30 PM`. */
export function formatClock(instant: Date): string {
  return clock.format(instant);
}

/**
 * When on a card: relative for the next 6 days, such as `Tomorrow 6:30 PM` or `Sat 7:00 AM`, and
 * a date after that, such as `Nov 14, 6:30 PM` (design document section 7.5).
 */
export function formatSoon(instant: Date, now: Date): string {
  const days = daysFrom(now, rexburgDate(instant));
  const time = clock.format(instant);
  if (NEARBY[days]) return `${NEARBY[days]} ${time}`;
  if (days > 1 && days < 7) return `${weekday.format(instant)} ${time}`;
  return `${monthDay.format(instant)}, ${time}`;
}

/** How long before `now` `instant` was, such as `just now`, `5m ago`, `2h ago` or `3d ago`. */
export function formatAgo(instant: Date, now: Date): string {
  const minutes = Math.floor((now.getTime() - instant.getTime()) / 60_000);
  if (minutes < 1) return 'just now';
  if (minutes < 60) return `${minutes}m ago`;
  if (minutes < 24 * 60) return `${Math.floor(minutes / 60)}h ago`;
  return `${Math.floor(minutes / (24 * 60))}d ago`;
}

/**
 * True once an activity is over: when it ends, or 3 hours after it starts without an end time.
 * rsvp() uses the same rule, and the feed shows activities for the same 3 hours.
 */
export function isOver(startsAt: Date, endsAt: Date | null, now: Date): boolean {
  return (endsAt?.getTime() ?? startsAt.getTime() + 3 * 60 * 60 * 1000) <= now.getTime();
}

/**
 * The instant when Rexburg's clocks show `date` and `time`, such as `2026-11-07` and `07:00`.
 * Daylight saving time is handled. A time the spring change skips comes out an hour earlier, and
 * a time the fall change repeats is the first of the two.
 */
export function rexburgInstant(date: string, time: string): Date {
  const [year, month, day] = date.split('-').map(Number);
  const [hour, minute] = time.split(':').map(Number);
  const wanted = Date.UTC(year, month - 1, day, hour, minute);
  // The offset at a first guess, then again at the corrected guess, in case a change lies between.
  let guess = wanted;
  for (let i = 0; i < 2; i++) guess = wanted - (wallClock(new Date(guess)) - guess);
  return new Date(guess);
}

/** The date chips (SRCH-02), as the `when` in a link, such as /discover?when=weekend. */
export const WHENS = { today: 'Today', week: 'This week', weekend: 'This weekend' } as const;

export type When = keyof typeof WHENS;

/** Start times from `from`, up to but not including `before`. */
export type StartRange = { from: Date; before: Date };

/**
 * The start times a date chip covers at `now`, in Rexburg (SRCH-02). This week runs through
 * Sunday, and this weekend from Friday at 5 PM through Sunday, so on a Saturday or Sunday it's the
 * one under way. The feed leaves out what's over, so on a Sunday this weekend is what's left of it.
 */
export function whenRange(when: When, now: Date): StartRange {
  const today = rexburgDate(now);
  const weekday = new Date(`${today}T00:00:00Z`).getUTCDay();
  const monday = addDays(today, (8 - weekday) % 7 || 7);
  if (when === 'today') return datesRange(today, today);
  const before = rexburgInstant(monday, '00:00');
  if (when === 'week') return { from: rexburgInstant(today, '00:00'), before };
  return { from: rexburgInstant(addDays(monday, -3), '17:00'), before };
}

/** The start times from the start of `first` to the end of `last`, dates in Rexburg (SRCH-02). */
export function datesRange(first: string, last: string): StartRange {
  return {
    from: rexburgInstant(first, '00:00'),
    before: rexburgInstant(addDays(last, 1), '00:00'),
  };
}
