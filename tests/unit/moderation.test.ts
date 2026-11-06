import { describe, expect, it } from 'vitest';
import {
  activityModeration,
  activityTransfer,
  dismissal,
  memberModeration,
} from '../../src/lib/validation/moderation';

describe('dismissal', () => {
  const form = { report_id: 'e0000000-0000-4000-8000-000000000091', reason: '  Not a sale  ' };

  it('trims the reason', () => {
    expect(dismissal.parse(form)).toEqual({ ...form, reason: 'Not a sale' });
  });

  it.each([
    ['reason', undefined, 'Give a reason. It goes to the audit log.'],
    ['reason', '   ', 'Give a reason. It goes to the audit log.'],
    ['reason', 'x'.repeat(501), 'Use 500 characters or fewer for the reason.'],
    ['report_id', 'not-an-id', undefined],
  ])('rejects a %s of %j', (field, value, message) => {
    const issue = dismissal.safeParse({ ...form, [field]: value }).error?.issues[0];
    expect(issue?.path).toEqual([field]);
    if (message) expect(issue?.message).toBe(message);
  });
});

describe('activityModeration', () => {
  const form = { activity_id: 'f0000000-0000-4000-8000-0000000000a1', reason: ' Selling tickets ' };

  it('trims the reason', () => {
    expect(activityModeration.parse(form)).toEqual({ ...form, reason: 'Selling tickets' });
  });

  it.each([
    ['reason', '', 'Give a reason. It goes to the audit log.'],
    ['activity_id', 'not-an-id', undefined],
  ])('rejects a %s of %j', (field, value, message) => {
    const issue = activityModeration.safeParse({ ...form, [field]: value }).error?.issues[0];
    expect(issue?.path).toEqual([field]);
    if (message) expect(issue?.message).toBe(message);
  });
});

describe('activityTransfer', () => {
  const form = {
    activity_id: 'f0000000-0000-4000-8000-0000000001b1',
    to_user: 'c0000000-0000-4000-8000-0000000001b4',
    reason: ' Gus agreed to host ',
  };

  it('trims the reason', () => {
    expect(activityTransfer.parse(form)).toEqual({ ...form, reason: 'Gus agreed to host' });
  });

  it.each([
    ['to_user', undefined, 'Pick the new host.'],
    ['to_user', '', 'Pick the new host.'],
    ['reason', '', 'Give a reason. It goes to the audit log.'],
  ])('rejects a %s of %j', (field, value, message) => {
    const issue = activityTransfer.safeParse({ ...form, [field]: value }).error?.issues[0];
    expect(issue?.path).toEqual([field]);
    expect(issue?.message).toBe(message);
  });
});

describe('memberModeration', () => {
  const form = { user_id: 'c0000000-0000-4000-8000-0000000000b4', reason: ' Harassment ' };

  it('trims the reason', () => {
    expect(memberModeration.parse(form)).toEqual({ ...form, reason: 'Harassment' });
  });

  it.each([
    ['reason', ' ', 'Give a reason. It goes to the audit log.'],
    ['user_id', 'not-an-id', undefined],
  ])('rejects a %s of %j', (field, value, message) => {
    const issue = memberModeration.safeParse({ ...form, [field]: value }).error?.issues[0];
    expect(issue?.path).toEqual([field]);
    if (message) expect(issue?.message).toBe(message);
  });
});
