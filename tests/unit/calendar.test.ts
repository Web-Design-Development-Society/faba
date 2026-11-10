import { describe, expect, it } from 'vitest';
import {
  escapeText,
  fold,
  googleCalendarUrl,
  icsFile,
  icsFilename,
  type CalendarEvent,
} from '../../src/lib/calendar';

// Saturday, December 5, 2026, 7:00 to 9:30 in Rexburg.
const hike: CalendarEvent = {
  id: 'f0000000-0000-4000-8000-000000000001',
  title: 'Sunrise hike up the R',
  startsAt: new Date('2026-12-05T14:00:00Z'),
  endsAt: new Date('2026-12-05T16:30:00Z'),
  place: 'R Mountain trailhead',
  description: 'Easy pace, about 3 miles.',
  url: 'https://faba.example/activities/f0000000-0000-4000-8000-000000000001',
  version: 2,
  cancelled: false,
};
const now = new Date('2026-11-10T22:30:00Z');

/** The file's lines, unfolded, as a calendar reads them. */
const linesOf = (file: string) => file.replace(/\r\n /g, '').split('\r\n');

describe('icsFile', () => {
  it('has the title, the time in UTC, the place, the FABA link and a stable UID', () => {
    expect(icsFile(hike, now)).toBe(
      [
        'BEGIN:VCALENDAR',
        'VERSION:2.0',
        'PRODID:-//FABA//Activities//EN',
        'CALSCALE:GREGORIAN',
        'METHOD:PUBLISH',
        'BEGIN:VEVENT',
        'UID:f0000000-0000-4000-8000-000000000001',
        'SEQUENCE:2',
        'DTSTAMP:20261110T223000Z',
        'DTSTART:20261205T140000Z',
        'DTEND:20261205T163000Z',
        'SUMMARY:Sunrise hike up the R',
        'LOCATION:R Mountain trailhead',
        // 75 octets, then the rest on the next line.
        'DESCRIPTION:Easy pace\\, about 3 miles.\\n\\nhttps://faba.example/activities/f',
        ' 0000000-0000-4000-8000-000000000001',
        'URL:https://faba.example/activities/f0000000-0000-4000-8000-000000000001',
        'STATUS:CONFIRMED',
        'END:VEVENT',
        'END:VCALENDAR',
        '',
      ].join('\r\n')
    );
  });

  it('lasts an hour without an end time', () => {
    expect(linesOf(icsFile({ ...hike, endsAt: null }, now))).toContain('DTEND:20261205T150000Z');
  });

  it('has the details for attendees only when given', () => {
    const description = (event: CalendarEvent) =>
      linesOf(icsFile(event, now)).find((line) => line.startsWith('DESCRIPTION:'));
    expect(description({ ...hike, privateDetails: '412 S 2nd W; gate code 4521' })).toBe(
      `DESCRIPTION:Easy pace\\, about 3 miles.\\n\\nFor attendees: 412 S 2nd W\\; gate code 4521\\n\\n${hike.url}`
    );
    expect(description({ ...hike, description: null, privateDetails: null })).toBe(
      `DESCRIPTION:${hike.url}`
    );
  });

  it('marks a cancelled activity cancelled', () => {
    expect(linesOf(icsFile({ ...hike, cancelled: true }, now))).toContain('STATUS:CANCELLED');
  });
});

describe('escapeText', () => {
  it('escapes backslashes, semicolons, commas and line breaks', () => {
    expect(escapeText('C:\\games; bring snacks, drinks\r\nand cards\nplease')).toBe(
      'C:\\\\games\\; bring snacks\\, drinks\\nand cards\\nplease'
    );
  });
});

describe('fold', () => {
  it('leaves a line of 75 octets as it is', () => {
    expect(fold('a'.repeat(75))).toBe('a'.repeat(75));
  });

  it('keeps every line to 75 octets without splitting a character', () => {
    const line = `SUMMARY:${'Café ☕ night 🎲 '.repeat(12)}`;
    const folded = fold(line);
    for (const part of folded.split('\r\n')) {
      expect(new TextEncoder().encode(part).length).toBeLessThanOrEqual(75);
    }
    expect(folded.replace(/\r\n /g, '')).toBe(line);
  });
});

describe('icsFilename', () => {
  it.each([
    ['Sunrise hike up the R', 'sunrise-hike-up-the-r.ics'],
    ['  Café & crêpes!  ', 'cafe-crepes.ics'],
    ['🎲🎲', 'activity.ics'],
    ['a'.repeat(80), `${'a'.repeat(60)}.ics`],
  ])('names %j %j', (title, name) => {
    expect(icsFilename(title)).toBe(name);
  });
});

describe('googleCalendarUrl', () => {
  it('opens a new event with the title, the time, the place and the FABA link', () => {
    const url = new URL(googleCalendarUrl(hike));
    expect(url.origin + url.pathname).toBe('https://calendar.google.com/calendar/render');
    expect(Object.fromEntries(url.searchParams)).toEqual({
      action: 'TEMPLATE',
      text: 'Sunrise hike up the R',
      dates: '20261205T140000Z/20261205T163000Z',
      location: 'R Mountain trailhead',
      details: `Easy pace, about 3 miles.\n\n${hike.url}`,
    });
  });

  it('leaves out the details for attendees', () => {
    expect(googleCalendarUrl({ ...hike, privateDetails: 'Gate code 4521' })).not.toContain('4521');
  });
});
