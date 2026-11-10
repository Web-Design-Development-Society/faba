import { describe, expect, it } from 'vitest';
import { newUpdate } from '../../src/lib/validation/update';

describe('newUpdate', () => {
  const form = {
    activity_id: 'f0000000-0000-4000-8000-000000000081',
    body: '  Bring a headlamp!\n',
    idempotency_key: 'a0000000-0000-4000-8000-000000000081',
  };

  it('trims the update', () => {
    expect(newUpdate.parse(form)).toEqual({ ...form, body: 'Bring a headlamp!' });
  });

  it('takes 500 characters', () => {
    expect(newUpdate.parse({ ...form, body: 'x'.repeat(500) }).body).toHaveLength(500);
  });

  it.each([
    ['body', ' \n ', 'Write your update.'],
    ['body', 'x'.repeat(501), 'Use 500 characters or fewer.'],
    ['activity_id', 'not-an-id', undefined],
    ['idempotency_key', undefined, undefined],
  ])('rejects a %s of %j', (field, value, message) => {
    const issue = newUpdate.safeParse({ ...form, [field]: value }).error?.issues[0];
    expect(issue?.path).toEqual([field]);
    if (message) expect(issue?.message).toBe(message);
  });
});
