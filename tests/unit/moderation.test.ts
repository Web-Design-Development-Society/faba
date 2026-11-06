import { describe, expect, it } from 'vitest';
import { activityModeration, dismissal } from '../../src/lib/validation/moderation';

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
