import { describe, expect, it } from 'vitest';
import {
  authCookieOptions,
  DEFAULT_NEXT_PATH,
  isAllowedEmail,
  safeNextPath,
} from '../../src/lib/server/auth';

describe('isAllowedEmail', () => {
  // The same cases as the database's hook tests (design document section 12.5).
  it.each([
    ['a@byui.edu', true],
    ['A@BYUI.EDU', true],
    ['a@student.byui.edu', false],
    ['a@byui.edu.evil.com', false],
    ['a@gmail.com', false],
    ['a@b@byui.edu', false],
    ['@byui.edu', false],
    ['', false],
    [null, false],
    [undefined, false],
  ])('%s → %s', (email, allowed) => {
    expect(isAllowedEmail(email, 'byui.edu')).toBe(allowed);
  });
});

describe('safeNextPath', () => {
  it.each([
    ['/discover', '/discover'],
    ['/activities/42?from=email#rsvp', '/activities/42?from=email#rsvp'],
    ['//evil.example/path', DEFAULT_NEXT_PATH],
    ['/\\evil.example', DEFAULT_NEXT_PATH],
    ['https://evil.example', DEFAULT_NEXT_PATH],
    ['discover', DEFAULT_NEXT_PATH],
    ['', DEFAULT_NEXT_PATH],
    [null, DEFAULT_NEXT_PATH],
  ])('%s → %s', (next, expected) => {
    expect(safeNextPath(next)).toBe(expected);
  });
});

describe('authCookieOptions', () => {
  it('keeps cookies away from page scripts and other sites', () => {
    expect(authCookieOptions(new URL('https://faba.example/'))).toEqual({
      httpOnly: true,
      secure: true,
      sameSite: 'lax',
      path: '/',
    });
  });

  it('drops Secure on plain-HTTP localhost', () => {
    expect(authCookieOptions(new URL('http://localhost:4321/')).secure).toBe(false);
  });
});
