// Comments on activities (ACT-12): the form's rules, as the database's CHECK constraint says.
import { describe, expect, it } from 'vitest';
import { newComment } from '../../src/lib/validation/comment';

const id = '00000000-0000-4000-8000-000000000001';

describe('newComment', () => {
  it('trims a comment and keeps it', () => {
    expect(newComment.parse({ activity_id: id, body: '  Is there parking?  ' }).body).toBe(
      'Is there parking?'
    );
  });

  it('refuses a blank comment', () => {
    const result = newComment.safeParse({ activity_id: id, body: '   ' });
    expect(result.success).toBe(false);
  });

  it('allows 500 characters and refuses 501', () => {
    expect(newComment.safeParse({ activity_id: id, body: 'a'.repeat(500) }).success).toBe(true);
    const long = newComment.safeParse({ activity_id: id, body: 'a'.repeat(501) });
    expect(long.success).toBe(false);
  });

  it('needs an activity', () => {
    expect(newComment.safeParse({ activity_id: 'nope', body: 'Hi' }).success).toBe(false);
  });
});
