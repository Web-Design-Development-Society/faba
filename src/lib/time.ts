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

const clock = new Intl.DateTimeFormat('en-US', {
  hour: 'numeric',
  minute: '2-digit',
  timeZone: TIME_ZONE,
});

/** A date and time for people, such as `Sat, Nov 7, 7:00 AM`. */
export function formatWhen(instant: Date): string {
  return when.format(instant);
}

/** A time for people, such as `9:30 AM`. */
export function formatClock(instant: Date): string {
  return clock.format(instant);
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
