import { describe, expect, it } from 'vitest';
import {
  addDays,
  formatAgo,
  formatDate,
  formatDay,
  formatRange,
  formatSoon,
  isOver,
  quickDates,
  rexburgDate,
  rexburgInstant,
  rexburgTime,
  whenRange,
  datesRange,
  type When,
} from '../../src/lib/time';

describe('addDays', () => {
  it.each([
    ['2026-12-31', 1, '2027-01-01'],
    ['2026-03-01', -1, '2026-02-28'],
    ['2026-11-07', 7, '2026-11-14'],
  ])('%s plus %i is %s', (date, days, moved) => {
    expect(addDays(date, days)).toBe(moved);
  });
});

describe('quickDates', () => {
  it.each([
    ['a Monday', '2026-11-02T17:00:00Z', '2026-11-02', '2026-11-03', '2026-11-07'],
    ['a Saturday', '2026-11-07T17:00:00Z', '2026-11-07', '2026-11-08', '2026-11-07'],
    ['a Sunday', '2026-11-08T17:00:00Z', '2026-11-08', '2026-11-09', '2026-11-14'],
    // 10:30 on Friday evening in Rexburg is already Saturday in UTC.
    ['a late Friday', '2026-11-07T05:30:00Z', '2026-11-06', '2026-11-07', '2026-11-07'],
  ])('on %s', (_, now, today, tomorrow, saturday) => {
    expect(quickDates(new Date(now))).toEqual({ today, tomorrow, saturday });
  });
});

describe('rexburgDate', () => {
  it.each([
    ['2026-11-02T06:59:00Z', '2026-11-01'],
    ['2026-11-02T07:00:00Z', '2026-11-02'],
    ['2026-07-04T05:59:00Z', '2026-07-03'],
    ['2026-07-04T06:00:00Z', '2026-07-04'],
  ])('%s is %s in Rexburg', (instant, date) => {
    expect(rexburgDate(new Date(instant))).toBe(date);
  });
});

describe('rexburgTime', () => {
  it.each([
    ['2026-11-02T17:00:00Z', '10:00'],
    ['2026-07-04T05:59:00Z', '23:59'],
  ])('%s is %s in Rexburg', (instant, time) => {
    expect(rexburgTime(new Date(instant))).toBe(time);
  });
});

describe('formatRange', () => {
  // Intl puts thin spaces around the dash and a narrow no-break space before AM.
  const plain = (text: string) => text.replace(/\s/g, ' ');

  it.each([
    ['2026-11-07T14:00:00Z', '2026-11-07T16:30:00Z', 'Sat, Nov 7, 7:00 – 9:30 AM'],
    ['2026-11-07T18:00:00Z', '2026-11-07T20:00:00Z', 'Sat, Nov 7, 11:00 AM – 1:00 PM'],
    ['2026-11-07T05:00:00Z', '2026-11-07T08:00:00Z', 'Fri, Nov 6, 10:00 PM – Sat, Nov 7, 1:00 AM'],
  ])('%s to %s is %s', (start, end, text) => {
    expect(plain(formatRange(new Date(start), new Date(end)))).toBe(text);
  });

  it('is the start without an end', () => {
    expect(plain(formatRange(new Date('2026-11-07T14:00:00Z'), null))).toBe('Sat, Nov 7, 7:00 AM');
  });
});

// 10:30 on Monday evening, November 2, in Rexburg, which is already Tuesday in UTC.
const monday = new Date('2026-11-03T05:30:00Z');

describe('formatDay', () => {
  it.each([
    ['2026-11-01', 'Yesterday'],
    ['2026-11-02', 'Today'],
    ['2026-11-03', 'Tomorrow'],
    ['2026-11-04', 'Wed, Nov 4'],
    ['2026-12-25', 'Fri, Dec 25'],
  ])('%s is %s', (date, heading) => {
    expect(formatDay(date, monday)).toBe(heading);
  });
});

describe('formatSoon', () => {
  const plain = (text: string) => text.replace(/\s/g, ' ');

  it.each([
    ['2026-11-02T05:00:00Z', 'Yesterday 10:00 PM'],
    ['2026-11-03T06:00:00Z', 'Today 11:00 PM'],
    ['2026-11-03T14:00:00Z', 'Tomorrow 7:00 AM'],
    ['2026-11-07T14:00:00Z', 'Sat 7:00 AM'],
    ['2026-11-09T01:30:00Z', 'Sun 6:30 PM'],
    ['2026-11-10T01:30:00Z', 'Nov 9, 6:30 PM'],
  ])('%s is %s', (instant, text) => {
    expect(plain(formatSoon(new Date(instant), monday))).toBe(text);
  });
});

describe('formatAgo', () => {
  const now = new Date('2026-11-02T17:00:00Z');

  it.each([
    ['2026-11-02T16:59:30Z', 'just now'],
    ['2026-11-02T16:55:00Z', '5m ago'],
    ['2026-11-02T16:00:01Z', '59m ago'],
    ['2026-11-02T16:00:00Z', '1h ago'],
    ['2026-11-01T17:00:01Z', '23h ago'],
    ['2026-10-30T17:00:00Z', '3d ago'],
  ])('says %s was %s', (instant, ago) => {
    expect(formatAgo(new Date(instant), now)).toBe(ago);
  });
});

describe('isOver', () => {
  const start = new Date('2026-11-07T14:00:00Z');

  it.each([
    ["isn't over before its end", '2026-11-07T15:00:00Z', '2026-11-07T14:59:00Z', false],
    ['is over at its end', '2026-11-07T15:00:00Z', '2026-11-07T15:00:00Z', true],
    ["isn't over 2:59 after it starts without an end", null, '2026-11-07T16:59:00Z', false],
    ['is over 3 hours after it starts without an end', null, '2026-11-07T17:00:00Z', true],
  ])('an activity %s', (_, end, now, over) => {
    expect(isOver(start, end ? new Date(end) : null, new Date(now))).toBe(over);
  });
});

describe('rexburgInstant', () => {
  it.each([
    // Mountain Daylight Time is UTC-6, and Mountain Standard Time is UTC-7.
    ['2026-07-04', '09:00', '2026-07-04T15:00:00.000Z'],
    ['2026-12-25', '09:00', '2026-12-25T16:00:00.000Z'],
    ['2026-12-31', '23:30', '2027-01-01T06:30:00.000Z'],
    // Clocks spring forward from 2:00 to 3:00 on March 8, 2026.
    ['2026-03-08', '01:30', '2026-03-08T08:30:00.000Z'],
    ['2026-03-08', '03:30', '2026-03-08T09:30:00.000Z'],
    ['2026-03-08', '02:30', '2026-03-08T08:30:00.000Z'],
    // And fall back from 2:00 to 1:00 on November 1, 2026, so 1:30 happens twice.
    ['2026-11-01', '01:30', '2026-11-01T07:30:00.000Z'],
    ['2026-11-01', '02:30', '2026-11-01T09:30:00.000Z'],
  ])('%s %s in Rexburg is %s', (date, time, instant) => {
    expect(rexburgInstant(date, time).toISOString()).toBe(instant);
  });
});

describe('whenRange', () => {
  const iso = ({ from, before }: { from: Date; before: Date }) => [
    from.toISOString(),
    before.toISOString(),
  ];

  it.each<[string, When, string, string, string]>([
    // Wednesday, November 11, 2026, at 3 PM in Rexburg (UTC-7)
    [
      'today',
      'today',
      '2026-11-11T22:00:00Z',
      '2026-11-11T07:00:00.000Z',
      '2026-11-12T07:00:00.000Z',
    ],
    // At 10 PM in Rexburg, it's already the next day in UTC.
    [
      'today, late',
      'today',
      '2026-11-12T05:00:00Z',
      '2026-11-11T07:00:00.000Z',
      '2026-11-12T07:00:00.000Z',
    ],
    [
      'this week, through Sunday',
      'week',
      '2026-11-11T22:00:00Z',
      '2026-11-11T07:00:00.000Z',
      '2026-11-16T07:00:00.000Z',
    ],
    [
      'this week, on a Sunday',
      'week',
      '2026-11-15T22:00:00Z',
      '2026-11-15T07:00:00.000Z',
      '2026-11-16T07:00:00.000Z',
    ],
    [
      'this week, on a Monday',
      'week',
      '2026-11-16T22:00:00Z',
      '2026-11-16T07:00:00.000Z',
      '2026-11-23T07:00:00.000Z',
    ],
    [
      'this weekend, from Friday at 5 PM',
      'weekend',
      '2026-11-11T22:00:00Z',
      '2026-11-14T00:00:00.000Z',
      '2026-11-16T07:00:00.000Z',
    ],
    [
      'this weekend, on a Friday morning',
      'weekend',
      '2026-11-13T17:00:00Z',
      '2026-11-14T00:00:00.000Z',
      '2026-11-16T07:00:00.000Z',
    ],
    [
      'this weekend, on a Saturday',
      'weekend',
      '2026-11-14T22:00:00Z',
      '2026-11-14T00:00:00.000Z',
      '2026-11-16T07:00:00.000Z',
    ],
    [
      'this weekend, on a Sunday',
      'weekend',
      '2026-11-15T22:00:00Z',
      '2026-11-14T00:00:00.000Z',
      '2026-11-16T07:00:00.000Z',
    ],
    // Clocks fall back on Sunday, November 1, 2026, so Friday is UTC-6 and Monday UTC-7.
    [
      'this weekend, as clocks fall back',
      'weekend',
      '2026-10-31T18:00:00Z',
      '2026-10-30T23:00:00.000Z',
      '2026-11-02T07:00:00.000Z',
    ],
    // And spring forward on Sunday, March 8, 2026, so Thursday is UTC-7 and Monday UTC-6.
    [
      'this week, as clocks spring forward',
      'week',
      '2026-03-05T18:00:00Z',
      '2026-03-05T07:00:00.000Z',
      '2026-03-09T06:00:00.000Z',
    ],
  ])('%s', (_, when, now, from, before) => {
    expect(iso(whenRange(when, new Date(now)))).toEqual([from, before]);
  });

  it('covers whole days for dates', () => {
    expect(iso(datesRange('2026-11-20', '2026-11-21'))).toEqual([
      '2026-11-20T07:00:00.000Z',
      '2026-11-22T07:00:00.000Z',
    ]);
  });
});

describe('formatDate', () => {
  it('has the year, since a series can end in the next one', () => {
    expect(formatDate('2027-11-07')).toBe('Nov 7, 2027');
  });
});
