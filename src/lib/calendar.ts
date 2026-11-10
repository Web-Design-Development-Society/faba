// Adding an activity to a member's own calendar (ACT-08, design document section 8.13): an .ics
// file, which Apple Calendar, Outlook and Google Calendar open, and a Google Calendar link. FABA
// never writes to anyone's calendar. The file follows RFC 5545.

/** An activity as a calendar event. */
export interface CalendarEvent {
  id: string;
  title: string;
  startsAt: Date;
  endsAt: Date | null;
  place: string;
  description: string | null;
  /** Its page on FABA. */
  url: string;
  /** Its edit version, so a download after an edit updates the event a calendar already has. */
  version: number;
  cancelled: boolean;
  /** Its details for attendees, only for a member going (ACT-09). */
  privateDetails?: string | null;
}

/** How long an event lasts in a calendar when the organizer gave no end time. */
export const DEFAULT_LENGTH = 60 * 60 * 1000;

/** The most octets on one line of the file, not counting its line break (RFC 5545 3.1). */
const LINE_OCTETS = 75;

const encoder = new TextEncoder();

/** When `event` ends in a calendar. */
function endOf(event: CalendarEvent): Date {
  return event.endsAt ?? new Date(event.startsAt.getTime() + DEFAULT_LENGTH);
}

/** `instant` in UTC, as both the file and Google's link write it, such as 20261205T020000Z. */
function utc(instant: Date): string {
  return instant.toISOString().replace(/[-:]|\.\d{3}/g, '');
}

/** `text` as a TEXT value, with backslashes, semicolons, commas and line breaks escaped. */
export function escapeText(text: string): string {
  return text.replace(/[\\;,]/g, (character) => `\\${character}`).replace(/\r?\n/g, '\\n');
}

/**
 * `line` split into lines of at most 75 octets, each after the first starting with a space, which
 * calendars remove when they read it. A character is never split.
 */
export function fold(line: string): string {
  const lines: string[] = [];
  let current = '';
  let octets = 0;
  for (const character of line) {
    const size = encoder.encode(character).length;
    if (octets + size > LINE_OCTETS) {
      lines.push(current);
      current = ' ';
      octets = 1;
    }
    current += character;
    octets += size;
  }
  lines.push(current);
  return lines.join('\r\n');
}

/** The event's notes: its description, its details for attendees if given, and its link. */
function notes(event: CalendarEvent, privateDetails: string | null | undefined): string {
  return [event.description, privateDetails && `For attendees: ${privateDetails}`, event.url]
    .filter(Boolean)
    .join('\n\n');
}

/**
 * The .ics file for `event`, made at `now`. Its UID is the activity's id, so it never changes,
 * and the edit version is its SEQUENCE. Times are in UTC, which every calendar shows in its own
 * time zone.
 */
export function icsFile(event: CalendarEvent, now: Date): string {
  const lines = [
    'BEGIN:VCALENDAR',
    'VERSION:2.0',
    'PRODID:-//FABA//Activities//EN',
    'CALSCALE:GREGORIAN',
    'METHOD:PUBLISH',
    'BEGIN:VEVENT',
    `UID:${event.id}`,
    `SEQUENCE:${event.version}`,
    `DTSTAMP:${utc(now)}`,
    `DTSTART:${utc(event.startsAt)}`,
    `DTEND:${utc(endOf(event))}`,
    `SUMMARY:${escapeText(event.title)}`,
    `LOCATION:${escapeText(event.place)}`,
    `DESCRIPTION:${escapeText(notes(event, event.privateDetails))}`,
    `URL:${event.url}`,
    `STATUS:${event.cancelled ? 'CANCELLED' : 'CONFIRMED'}`,
    'END:VEVENT',
    'END:VCALENDAR',
  ];
  return `${lines.map(fold).join('\r\n')}\r\n`;
}

/** A file name for the .ics, from the activity's title, such as sunrise-hike-up-the-r.ics. */
export function icsFilename(title: string): string {
  const name = title
    .normalize('NFKD')
    .replace(/\p{M}/gu, '')
    .toLowerCase()
    .replace(/[^a-z0-9]+/g, '-')
    .slice(0, 60)
    .replace(/^-+|-+$/g, '');
  return `${name || 'activity'}.ics`;
}

/**
 * A Google Calendar link that opens `event` as a new event. It leaves out the details for
 * attendees, since a link's text reaches Google and stays in the browser's history. Its notes
 * link to FABA, where a member going can read them.
 */
export function googleCalendarUrl(event: CalendarEvent): string {
  const url = new URL('https://calendar.google.com/calendar/render');
  url.searchParams.set('action', 'TEMPLATE');
  url.searchParams.set('text', event.title);
  url.searchParams.set('dates', `${utc(event.startsAt)}/${utc(endOf(event))}`);
  url.searchParams.set('location', event.place);
  url.searchParams.set('details', notes(event, null));
  return url.href;
}
