import { describe, expect, it } from 'vitest';
import {
  afterSignInPath,
  authCookieOptions,
  callbackFailure,
  DEFAULT_NEXT_PATH,
  googleSignInOptions,
  isAllowedEmail,
  isInAppBrowser,
  safeNextPath,
  signInErrorMessage,
  signInErrorPath,
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

  it.each([
    ['http://localhost:4321/', false],
    ['http://127.0.0.1:4321/', false],
    ['https://localhost:4321/', true],
    // Elsewhere, cookies stay Secure even over plain HTTP, so they can't leak there.
    ['http://faba.example/', true],
  ])('%s → Secure %s', (url, secure) => {
    expect(authCookieOptions(new URL(url)).secure).toBe(secure);
  });
});

describe('googleSignInOptions', () => {
  it('returns to the same site and steers Google to byui.edu', () => {
    expect(
      googleSignInOptions(new URL('https://pr-7-faba.example/auth/login'), 'byui.edu')
    ).toEqual({
      redirectTo: 'https://pr-7-faba.example/auth/callback',
      scopes: 'openid',
      queryParams: { hd: 'byui.edu', prompt: 'select_account' },
    });
  });
});

describe('callbackFailure', () => {
  it.each([
    ['error=access_denied&error_description=The+user+denied+access', 'cancelled'],
    [
      'error=access_denied&error_description=FABA+is+for+BYU-Idaho.+Sign+in+with+your+byui.edu+account.',
      'not-eligible',
    ],
    ['error=server_error&error_description=Unable+to+exchange+external+code', 'failed'],
    ['', 'failed'],
  ])('%s → %s', (query, failure) => {
    expect(callbackFailure(new URLSearchParams(query), 'byui.edu')).toBe(failure);
  });
});

describe('sign-in errors', () => {
  it('has a message for each error, and none without one', () => {
    expect(signInErrorMessage('cancelled')).toMatch(/didn't finish signing in/);
    expect(signInErrorMessage('failed')).toMatch(/didn't work/);
    expect(signInErrorMessage('<script>')).toBe(signInErrorMessage('failed'));
    expect(signInErrorMessage(null)).toBeNull();
  });

  it('keeps the page to return to', () => {
    expect(signInErrorPath('cancelled', DEFAULT_NEXT_PATH)).toBe('/?error=cancelled');
    expect(signInErrorPath('failed', '/activities/42')).toBe(
      '/?error=failed&next=%2Factivities%2F42'
    );
  });
});

describe('afterSignInPath', () => {
  it.each([
    [false, '/activities/42', '/activities/42'],
    [true, DEFAULT_NEXT_PATH, '/welcome'],
    [true, '/activities/42', '/welcome?next=%2Factivities%2F42'],
  ])('new member %s, next %s → %s', (isNewMember, next, expected) => {
    expect(afterSignInPath(isNewMember, next)).toBe(expected);
  });
});

describe('isInAppBrowser', () => {
  it.each([
    [
      'Instagram on iPhone',
      'Mozilla/5.0 (iPhone; CPU iPhone OS 18_1 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Mobile/15E148 Instagram 357.0.0.25.101 (iPhone14,5; iOS 18_1; en_US; en; scale=3.00; 1170x2532; 659391232)',
    ],
    [
      'Messenger on iPhone',
      'Mozilla/5.0 (iPhone; CPU iPhone OS 18_1 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Mobile/15E148 [FBAN/MessengerLiteForiOS;FBAV/480.0.0.40.110;FBBV/655468201;FBDV/iPhone14,5;FBMD/iPhone;FBSN/iOS;FBSV/18.1;FBSS/3;FBCR/;FBID/phone;FBLC/en_US;FBOP/0]',
    ],
    [
      'LinkedIn on iPhone',
      'Mozilla/5.0 (iPhone; CPU iPhone OS 18_1 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Mobile/15E148 [LinkedInApp]/9.30.2383',
    ],
    [
      'an Android WebView',
      'Mozilla/5.0 (Linux; Android 14; Pixel 7 Build/AP2A.240905.003; wv) AppleWebKit/537.36 (KHTML, like Gecko) Version/4.0 Chrome/130.0.6723.58 Mobile Safari/537.36',
    ],
  ])('detects %s', (_, userAgent) => {
    expect(isInAppBrowser(userAgent)).toBe(true);
  });

  it.each([
    [
      'Safari on iPhone',
      'Mozilla/5.0 (iPhone; CPU iPhone OS 18_1 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/18.1 Mobile/15E148 Safari/604.1',
    ],
    [
      'Chrome on iPhone',
      'Mozilla/5.0 (iPhone; CPU iPhone OS 18_1 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) CriOS/130.0.6723.90 Mobile/15E148 Safari/604.1',
    ],
    [
      'Chrome on Android',
      'Mozilla/5.0 (Linux; Android 10; K) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/130.0.0.0 Mobile Safari/537.36',
    ],
    ['no user agent', null],
  ])('leaves %s alone', (_, userAgent) => {
    expect(isInAppBrowser(userAgent)).toBe(false);
  });
});
