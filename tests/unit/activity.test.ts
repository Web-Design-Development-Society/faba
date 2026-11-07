import { afterAll, beforeAll, describe, expect, it, vi } from 'vitest';
import { isFull } from '../../src/lib/cards';
import { actionErrorFor } from '../../src/lib/server/errors';
import {
  activityChanges,
  cancellation,
  descriptionChange,
  newActivity,
  suggestedStart,
} from '../../src/lib/validation/activity';

// Monday, November 2, 2026, at 10:00 in Rexburg.
beforeAll(() => {
  vi.useFakeTimers();
  vi.setSystemTime(new Date('2026-11-02T17:00:00Z'));
});
afterAll(() => {
  vi.useRealTimers();
});

const valid = {
  idempotency_key: '7c9e6679-7425-40de-944b-e07fc1f90ae7',
  title: '  Sunrise hike  ',
  date: '2026-11-07',
  start_time: '07:00',
  location_name: ' R Mountain trailhead ',
  category_id: 'outdoors',
};

/** Each field's first message, as an Action's input error lists them. */
function errors(input: Record<string, unknown>) {
  const result = newActivity.safeParse({ ...valid, ...input });
  if (result.success) return {};
  return Object.fromEntries(result.error.issues.map(({ path, message }) => [path[0], message]));
}

describe('newActivity', () => {
  it('turns the form into create_activity() arguments, in Rexburg time', () => {
    expect(newActivity.parse({ ...valid, end_time: '09:30', cost_note: ' Free ' })).toEqual({
      idempotency_key: valid.idempotency_key,
      title: 'Sunrise hike',
      location_name: 'R Mountain trailhead',
      category_id: 'outdoors',
      cost_note: 'Free',
      starts_at: '2026-11-07T14:00:00.000Z',
      ends_at: '2026-11-07T16:30:00.000Z',
    });
  });

  it('leaves out an end time that is empty', () => {
    expect(newActivity.parse(valid).ends_at).toBeUndefined();
  });

  it('says what each empty required field needs', () => {
    // Astro passes an empty required field as null.
    expect(
      errors({ title: null, date: null, start_time: null, location_name: null, category_id: null })
    ).toEqual({
      title: 'Add a title.',
      date: 'Choose a date.',
      start_time: 'Choose a start time.',
      location_name: 'Add a place.',
      category_id: 'Choose a category.',
    });
  });

  it.each([
    ['title', ' Hi ', 'Use at least 3 characters.'],
    ['title', 'a'.repeat(81), 'Use 80 characters or fewer.'],
    ['location_name', '  ', 'Add a place.'],
    ['location_name', 'a'.repeat(121), 'Use 120 characters or fewer.'],
    ['description', 'a'.repeat(2001), 'Use 2000 characters or fewer.'],
    ['cost_note', 'a'.repeat(61), 'Use 60 characters or fewer.'],
    ['date', '2026-02-30', 'Choose a date.'],
  ])('rejects %s %j', (field, value, message) => {
    expect(errors({ [field]: value })).toEqual({ [field]: message });
  });

  it.each([
    ['earlier today', { date: '2026-11-02', start_time: '09:59' }, 'start_time'],
    ['right now', { date: '2026-11-02', start_time: '10:00' }, 'start_time'],
    ['more than 12 months ahead', { date: '2027-11-02', start_time: '11:01' }, 'date'],
    ['ending when it starts', { end_time: '07:00' }, 'end_time'],
    ['ending before it starts', { end_time: '06:00' }, 'end_time'],
  ])('rejects an activity %s', (_, input, field) => {
    expect(Object.keys(errors(input))).toEqual([field]);
  });

  it.each([
    ['later today', { date: '2026-11-02', start_time: '10:01' }],
    ['exactly 12 months ahead', { date: '2027-11-02', start_time: '11:00' }],
  ])('accepts an activity %s', (_, input) => {
    expect(errors(input)).toEqual({});
  });

  it.each([
    [0, 'Allow at least 1 spot.'],
    [501, 'Allow 500 spots or fewer.'],
    [2.5, 'Enter a whole number of spots.'],
    [Number.NaN, 'Enter a number of spots, or leave it empty.'],
  ])('rejects %s spots', (capacity, message) => {
    expect(errors({ capacity })).toEqual({ capacity: message });
  });

  it('takes Guests welcome and the most each member can bring', () => {
    expect(
      newActivity.parse({ ...valid, guests_allowed: true, max_guests_per_rsvp: 2 })
    ).toMatchObject({ guests_allowed: true, max_guests_per_rsvp: 2 });
    expect(errors({ max_guests_per_rsvp: 6 })).toEqual({
      max_guests_per_rsvp: 'Allow 5 guests each or fewer.',
    });
    expect(errors({ max_guests_per_rsvp: 0 })).toEqual({
      max_guests_per_rsvp: 'Allow at least 1 guest each.',
    });
  });

  it('takes up to 3 tags', () => {
    expect(newActivity.parse({ ...valid, tags: ['free', 'accessible'] }).tags).toEqual([
      'free',
      'accessible',
    ]);
    expect(errors({ tags: ['a', 'b', 'c', 'd'] })).toEqual({ tags: 'Pick up to 3 tags.' });
  });

  it('takes a number of spots, or none', () => {
    expect(newActivity.parse({ ...valid, capacity: 12 }).capacity).toBe(12);
    expect(newActivity.parse(valid).capacity).toBeUndefined();
  });
});

describe('isFull', () => {
  it.each([
    [{ going_count: 4, guest_total: 0, capacity: 5 }, false],
    [{ going_count: 4, guest_total: 1, capacity: 5 }, true],
    [{ going_count: 7, guest_total: 0, capacity: 5 }, true],
    [{ going_count: 400, guest_total: 0, capacity: null }, false],
  ])('%j is full: %s', (activity, full) => {
    expect(isFull(activity)).toBe(full);
  });
});

describe('activityChanges', () => {
  const edit = { ...valid, id: 'f0000000-0000-4000-8000-000000000001', version: 3 };

  it("turns the edit form into update_activity()'s patch, with the id and version", () => {
    expect(activityChanges.parse({ ...edit, end_time: '09:30' })).toEqual({
      id: edit.id,
      version: 3,
      title: 'Sunrise hike',
      location_name: 'R Mountain trailhead',
      category_id: 'outdoors',
      starts_at: '2026-11-07T14:00:00.000Z',
      ends_at: '2026-11-07T16:30:00.000Z',
    });
  });

  it("has the create form's rules", () => {
    const result = activityChanges.safeParse({
      ...edit,
      title: 'Hi',
      start_time: '06:00',
      end_time: '05:00',
    });
    expect(result.error?.issues.map(({ path }) => path[0])).toEqual(['title', 'end_time']);
  });
});

describe('descriptionChange', () => {
  const id = 'f0000000-0000-4000-8000-000000000001';

  it('takes only the description', () => {
    expect(descriptionChange.parse({ ...valid, id, version: 2, description: ' Thanks! ' })).toEqual(
      {
        id,
        version: 2,
        description: 'Thanks!',
      }
    );
  });

  it("has the create form's limit", () => {
    expect(
      descriptionChange.safeParse({ id, version: 2, description: 'a'.repeat(2001) }).success
    ).toBe(false);
  });
});

describe('cancellation', () => {
  const id = 'f0000000-0000-4000-8000-000000000001';

  it('takes an optional reason, trimmed', () => {
    expect(cancellation.parse({ id, reason: ' Rained out ' })).toEqual({
      id,
      reason: 'Rained out',
    });
    expect(cancellation.parse({ id })).toEqual({ id });
  });

  it('keeps the reason to 200 characters', () => {
    expect(cancellation.safeParse({ id, reason: 'a'.repeat(200) }).success).toBe(true);
    expect(cancellation.safeParse({ id, reason: 'a'.repeat(201) }).error?.issues[0].message).toBe(
      'Use 200 characters or fewer for the reason.'
    );
  });
});

describe('suggestedStart', () => {
  it.each([
    ['2026-11-02T17:05:00Z', '2026-11-03T17:30:00.000Z'],
    ['2026-11-02T17:30:00Z', '2026-11-03T17:30:00.000Z'],
    ['2026-11-02T17:31:00Z', '2026-11-03T18:00:00.000Z'],
  ])('suggests %s for %s', (now, start) => {
    expect(suggestedStart(new Date(now)).toISOString()).toBe(start);
  });
});

describe('actionErrorFor', () => {
  it('gives the daily limit a friendly message', () => {
    expect(actionErrorFor({ message: 'QUOTA_EXCEEDED' })).toEqual({
      code: 'TOO_MANY_REQUESTS',
      message: 'You can post up to 10 activities a day. Try again tomorrow.',
    });
  });

  it('logs an unknown error with a reference that the message repeats', () => {
    const log = vi.spyOn(console, 'error').mockImplementation(() => {});
    const { code, message } = actionErrorFor({ message: 'boom', code: 'XX000' });
    expect(code).toBe('INTERNAL_SERVER_ERROR');
    const reference = message.match(/\(Reference (\w{8})\)$/)?.[1];
    expect(reference).toBeDefined();
    expect(JSON.parse(log.mock.calls[0][0])).toEqual({ reference, code: 'XX000', message: 'boom' });
    log.mockRestore();
  });
});
