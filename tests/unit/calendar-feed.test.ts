import { describe, expect, it } from 'vitest';
import { icsFeed, type CalendarEvent } from '../../src/lib/calendar';
import { hashFeedToken, newFeedToken } from '../../src/lib/calendar-feed';

const now = new Date('2026-11-10T12:00:00Z');

function event(id: string, title: string, cancelled = false): CalendarEvent {
  return {
    id,
    title,
    startsAt: new Date('2026-12-05T02:00:00Z'),
    endsAt: null,
    place: 'Park',
    description: null,
    url: `https://faba.example/activities/${id}`,
    version: 2,
    cancelled,
  };
}

describe('newFeedToken', () => {
  it('makes a 32-byte token in URL-safe base64, which is different each time', () => {
    const token = newFeedToken();
    expect(token).toMatch(/^[A-Za-z0-9_-]{43}$/);
    expect(newFeedToken()).not.toBe(token);
  });
});

describe('hashFeedToken', () => {
  it('is a hex SHA-256, the same for the same token', async () => {
    const hash = await hashFeedToken('example-token');
    expect(hash).toMatch(/^[0-9a-f]{64}$/);
    expect(await hashFeedToken('example-token')).toBe(hash);
    expect(await hashFeedToken('another-token')).not.toBe(hash);
  });
});

describe('icsFeed', () => {
  it('writes one calendar with an event for each activity, in order', () => {
    const file = icsFeed([event('a1', 'Picnic'), event('b2', 'Hike', true)], now);
    expect(file.match(/BEGIN:VCALENDAR/g)).toHaveLength(1);
    expect(file.match(/BEGIN:VEVENT/g)).toHaveLength(2);
    expect(file.indexOf('UID:a1')).toBeLessThan(file.indexOf('UID:b2'));
    expect(file).toContain('STATUS:CANCELLED');
    expect(file.endsWith('END:VCALENDAR\r\n')).toBe(true);
  });

  it('is an empty calendar when there are no activities', () => {
    const file = icsFeed([], now);
    expect(file).not.toContain('BEGIN:VEVENT');
    expect(file).toContain('BEGIN:VCALENDAR');
  });
});
