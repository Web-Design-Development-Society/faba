import { describe, expect, it } from 'vitest';
import { addDays, quickDates, rexburgDate, rexburgInstant, rexburgTime } from '../../src/lib/time';

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
