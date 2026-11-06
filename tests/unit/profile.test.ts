import { describe, expect, it } from 'vitest';
import { accountDeletion, displayName, profileChanges } from '../../src/lib/validation/profile';

describe('displayName', () => {
  it.each([
    ['Maya Member', 'Maya Member'],
    ['  Jo  ', 'Jo'],
    ['x'.repeat(50), 'x'.repeat(50)],
  ])('accepts %j as %j', (input, expected) => {
    expect(displayName.parse(input)).toBe(expected);
  });

  it.each([
    ['J', 'Use at least 2 characters.'],
    ['   ', 'Use at least 2 characters.'],
    ['x'.repeat(51), 'Use 50 characters or fewer.'],
  ])('rejects %j', (input, message) => {
    expect(displayName.safeParse(input).error?.issues[0].message).toBe(message);
  });
});

describe('profileChanges', () => {
  const form = {
    display_name: ' Elle ',
    use_initials: false,
    department: ' Mathematics ',
    bio: '',
    interests: ['outdoors', 'games'],
    faculty_type: 'part_time',
    email_visible: true,
  };

  it('trims the text and keeps the choices', () => {
    expect(profileChanges.parse(form)).toEqual({
      ...form,
      display_name: 'Elle',
      department: 'Mathematics',
    });
  });

  it('leaves out what was left empty', () => {
    expect(
      profileChanges.parse({
        display_name: 'Elle',
        use_initials: true,
        interests: [],
        email_visible: false,
      })
    ).toEqual({ display_name: 'Elle', use_initials: true, interests: [], email_visible: false });
  });

  it.each([
    ['department', 'x'.repeat(61), 'Use 60 characters or fewer.'],
    ['bio', 'x'.repeat(281), 'Use 280 characters or fewer.'],
    ['faculty_type', 'adjunct', undefined],
  ])('rejects a %s of %j', (field, value, message) => {
    const issue = profileChanges.safeParse({ ...form, [field]: value }).error?.issues[0];
    expect(issue?.path).toEqual([field]);
    if (message) expect(issue?.message).toBe(message);
  });

  it('takes 20 interests at most', () => {
    const interests = Array.from({ length: 21 }, (_, n) => `category-${n}`);
    expect(profileChanges.safeParse({ ...form, interests }).success).toBe(false);
  });
});

describe('accountDeletion', () => {
  it('takes DELETE, typed exactly', () => {
    expect(accountDeletion.parse({ confirm: ' DELETE ' })).toEqual({ confirm: 'DELETE' });
  });

  it.each([undefined, '', 'delete', 'DELETE ME'])('rejects %j', (confirm) => {
    expect(accountDeletion.safeParse({ confirm }).error?.issues[0].message).toBe(
      'Type DELETE to confirm.'
    );
  });
});
