// Push (NOTIF-20): what a push says, where tapping a notification goes, and what a push service's
// answer means.
import { describe, expect, it } from 'vitest';
import {
  notificationHref,
  PREFERENCE_TYPES,
  PUSH_DEFAULT_TYPES,
  pushMessage,
  TYPES,
} from '../../src/lib/notifications';
import { outcomeOf } from '../../src/lib/server/push/send';

const id = '6f1d2c3b-4a5e-4f60-8a7b-9c0d1e2f3a4b';

describe('pushMessage', () => {
  it('says what it is about, with the same line as Alerts', () => {
    const now = new Date('2026-12-03T17:00:00Z');
    expect(
      pushMessage(
        {
          notification_id: id,
          type: 'activity_changed',
          payload: {
            title: 'Pickleball night',
            before: { starts_at: '2026-12-05T02:00:00Z' },
            after: { starts_at: '2026-12-05T02:30:00Z' },
          },
        },
        now
      )
    ).toEqual({
      id,
      title: 'Pickleball night',
      body: 'Moved to Fri, Dec 4, 7:30 PM (was 7:00 PM)',
      url: `/notifications/${id}`,
    });
  });

  it('never shows an update’s message, only that there is one', () => {
    for (const type of ['organizer_update', 'group_update']) {
      const { body } = pushMessage({
        notification_id: id,
        type,
        payload: { title: 'Hike', body: 'The gate code is 1234' },
      });
      expect(body).toBe(TYPES[type].summary);
    }
  });

  it('uses the group’s name, or FABA, when there is no title', () => {
    expect(
      pushMessage({ notification_id: id, type: 'group_join_approved', payload: { name: 'Hikers' } })
        .title
    ).toBe('Hikers');
    expect(pushMessage({ notification_id: id, type: 'reminder', payload: null }).title).toBe(
      'FABA'
    );
  });
});

describe('PUSH_DEFAULT_TYPES', () => {
  it('are the urgent changes to plans, and each is a type there is', () => {
    expect(PUSH_DEFAULT_TYPES).toEqual([
      'activity_changed',
      'activity_cancelled',
      'activity_restored',
      'reminder',
      'rsvp_promoted',
      'rsvp_removed',
      'sub_needed',
    ]);
    for (const type of PUSH_DEFAULT_TYPES) expect(TYPES).toHaveProperty(type);
    expect(PREFERENCE_TYPES).not.toContain('activity_cancelled');
  });
});

describe('notificationHref', () => {
  it('opens the activity', () => {
    expect(
      notificationHref({ type: 'reminder', activity_id: 'a1', payload: {}, group_slug: null })
    ).toBe('/activities/a1');
  });

  it('opens the group, and a join request its members', () => {
    expect(
      notificationHref({ type: 'group_update', activity_id: null, payload: {}, group_slug: 'hike' })
    ).toBe('/groups/hike');
    expect(
      notificationHref({
        type: 'group_join_request',
        activity_id: null,
        payload: {},
        group_slug: 'hike',
      })
    ).toBe('/groups/hike/members');
  });

  it('opens the page a follow notice or a report names, on this site only', () => {
    expect(
      notificationHref({
        type: 'new_activity',
        activity_id: null,
        payload: { href: '/discover?cat=outdoors' },
      })
    ).toBe('/discover?cat=outdoors');
    expect(
      notificationHref({
        type: 'report_received',
        activity_id: null,
        payload: { href: 'https://example.com' },
      })
    ).toBe('/notifications');
  });

  it('opens Alerts when it points nowhere', () => {
    expect(notificationHref({ type: 'reminder', activity_id: null, payload: {} })).toBe(
      '/notifications'
    );
  });
});

describe('outcomeOf', () => {
  it('reads the push service’s answer', () => {
    expect(outcomeOf(201)).toBe('sent');
    expect(outcomeOf(410)).toBe('gone');
    expect(outcomeOf(404)).toBe('gone');
    expect(outcomeOf(429)).toBe('retry');
    expect(outcomeOf(503)).toBe('retry');
    expect(outcomeOf(400)).toBe('failed');
    expect(outcomeOf(413)).toBe('failed');
  });
});
