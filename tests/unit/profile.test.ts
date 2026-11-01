import { describe, expect, it } from 'vitest';
import { displayName } from '../../src/lib/validation/profile';

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
