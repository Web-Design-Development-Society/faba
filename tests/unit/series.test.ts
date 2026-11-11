import { describe, expect, it } from 'vitest';
import {
  monthlyLabels,
  nthWeekday,
  ordinalDay,
  repeatsBadge,
  repeatsSentence,
  weekdayName,
  weekdayWarning,
} from '../../src/lib/series';

describe('weekdayName', () => {
  it('names the weekday a date falls on', () => {
    expect(weekdayName('2027-01-12')).toBe('Tuesday');
    expect(weekdayName('2027-03-14')).toBe('Sunday');
  });
});

describe('weekdayWarning', () => {
  it('warns when this and future dates move to another weekday (REC-02)', () => {
    expect(weekdayWarning('2027-01-12', '2027-01-14')).toBe(
      "Future dates move from Tuesdays to Thursdays. People going stay going, and they're told."
    );
  });

  it('says nothing for the same weekday, a week on or not', () => {
    expect(weekdayWarning('2027-01-12', '2027-01-12')).toBe('');
    expect(weekdayWarning('2027-01-12', '2027-01-19')).toBe('');
  });
});

describe('ordinalDay', () => {
  it.each([
    ['2027-01-01', '1st'],
    ['2027-01-02', '2nd'],
    ['2027-01-03', '3rd'],
    ['2027-01-04', '4th'],
    ['2027-01-11', '11th'],
    ['2027-01-12', '12th'],
    ['2027-01-13', '13th'],
    ['2027-01-21', '21st'],
    ['2027-01-22', '22nd'],
    ['2027-01-23', '23rd'],
    ['2027-01-31', '31st'],
  ])('%s is the %s', (date, ordinal) => {
    expect(ordinalDay(date)).toBe(ordinal);
  });
});

describe('nthWeekday', () => {
  it.each([
    ['2027-01-12', '2nd Tuesday'],
    ['2027-01-01', '1st Friday'],
    ['2027-01-28', '4th Thursday'],
    // A 5th one is the last, since a month always has a last one.
    ['2027-01-29', 'last Friday'],
    ['2027-01-31', 'last Sunday'],
  ])('%s is the %s', (date, which) => {
    expect(nthWeekday(date)).toBe(which);
  });
});

describe('monthlyLabels', () => {
  it('names the date and the weekday', () => {
    expect(monthlyLabels('2027-01-12')).toEqual({
      weekly: 'Weekly',
      biweekly: 'Every 2 weeks',
      monthly_date: 'Monthly on the 12th',
      monthly_nth: 'Monthly on the 2nd Tuesday',
    });
  });

  it('is general without a date', () => {
    expect(monthlyLabels()).toEqual({
      weekly: 'Weekly',
      biweekly: 'Every 2 weeks',
      monthly_date: 'Monthly on the same date',
      monthly_nth: 'Monthly on the same weekday',
    });
  });
});

describe('repeatsBadge', () => {
  it.each([
    ['weekly', 'Weekly'],
    ['biweekly', 'Every 2 weeks'],
    ['monthly_date', 'Monthly'],
    ['monthly_nth', 'Monthly'],
  ])('%s is %s on a card', (freq, badge) => {
    expect(repeatsBadge(freq)).toBe(badge);
  });
});

describe('repeatsSentence', () => {
  it.each([
    ['weekly', 'Repeats weekly'],
    ['biweekly', 'Repeats every 2 weeks'],
    ['monthly_date', 'Repeats monthly on the 29th'],
    ['monthly_nth', 'Repeats monthly on the last Friday'],
  ])('%s from January 29 is "%s"', (freq, sentence) => {
    expect(repeatsSentence(freq, '2027-01-29')).toBe(sentence);
  });
});
