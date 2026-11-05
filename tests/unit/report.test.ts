import { describe, expect, it } from 'vitest';
import { newReport } from '../../src/lib/validation/report';

describe('newReport', () => {
  const form = {
    target_type: 'activity',
    target_id: 'f0000000-0000-4000-8000-000000000081',
    reason: 'spam',
    note: '  Selling tickets  ',
  };

  it('trims the note', () => {
    expect(newReport.parse(form)).toEqual({ ...form, note: 'Selling tickets' });
  });

  it('takes no note', () => {
    expect(newReport.parse({ ...form, note: undefined })).toEqual({ ...form, note: undefined });
  });

  it.each([
    ['reason', undefined, 'Choose a reason.'],
    ['reason', 'rude', 'Choose a reason.'],
    ['note', 'x'.repeat(501), 'Use 500 characters or fewer for the note.'],
    ['target_type', 'category', undefined],
    ['target_id', 'not-an-id', undefined],
  ])('rejects a %s of %j', (field, value, message) => {
    const issue = newReport.safeParse({ ...form, [field]: value }).error?.issues[0];
    expect(issue?.path).toEqual([field]);
    if (message) expect(issue?.message).toBe(message);
  });
});
