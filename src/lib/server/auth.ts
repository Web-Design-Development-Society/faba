// Sign-in helpers that don't depend on Astro or Supabase, so unit tests can import them.
// Design document section 9.7.

/** Where people go after signing in when there's nowhere else to return to. */
export const DEFAULT_NEXT_PATH = '/discover';

/** Holds the path to return to while someone is away signing in with Google. */
export const NEXT_COOKIE = 'faba-next';

/**
 * True when the part after the @ is exactly `domain`, ignoring case. It matches the database's
 * private.is_allowed_email(), so subdomains and lookalike domains don't count.
 */
export function isAllowedEmail(email: unknown, domain: string): boolean {
  if (typeof email !== 'string') return false;
  const at = email.indexOf('@');
  return (
    at > 0 &&
    at === email.lastIndexOf('@') &&
    email.slice(at + 1).toLowerCase() === domain.toLowerCase()
  );
}

/** The parts of a Supabase user that the callback check reads. */
interface SignedInUser {
  email?: string;
  identities?: { provider: string; identity_data?: Record<string, unknown> }[];
}

/**
 * The callback check (ADR-005): the account's email and the email Google reported are both
 * allowed, and Google says it verified that email. Supabase's own email_confirmed_at doesn't
 * count, because Supabase sets it for every account when email confirmations are off.
 */
export function isEligibleGoogleUser(user: SignedInUser, domain: string): boolean {
  const google = user.identities?.find(({ provider }) => provider === 'google')?.identity_data;
  return (
    isAllowedEmail(user.email, domain) &&
    isAllowedEmail(google?.email, domain) &&
    google?.email_verified === true
  );
}

/**
 * A path on this site to return to after signing in. Anything that would leave the site, such as
 * `//example.com` or `/\example.com`, falls back to the default.
 */
export function safeNextPath(next: unknown): string {
  if (typeof next !== 'string' || !next.startsWith('/')) return DEFAULT_NEXT_PATH;
  const base = 'https://faba.invalid';
  const url = new URL(next, base);
  return url.origin === base ? url.pathname + url.search + url.hash : DEFAULT_NEXT_PATH;
}

/** `path`, with `next` added when it isn't the default. */
function withNext(path: string, next: string) {
  if (next === DEFAULT_NEXT_PATH) return path;
  return `${path}${path.includes('?') ? '&' : '?'}next=${encodeURIComponent(next)}`;
}

const LOOPBACK_HOSTS = new Set(['localhost', '127.0.0.1', '[::1]']);

/**
 * Options for every auth cookie. Page scripts can't read them, and they're sent only over HTTPS,
 * except on plain-HTTP localhost in development.
 */
export function authCookieOptions(url: URL) {
  return {
    httpOnly: true,
    secure: url.protocol === 'https:' || !LOOPBACK_HOSTS.has(url.hostname),
    sameSite: 'lax',
    path: '/',
  } as const;
}

/** The options for Supabase's signInWithOAuth() with Google. Supabase adds PKCE. */
export function googleSignInOptions(url: URL, domain: string) {
  return {
    // Back to this request's own site, so pull request previews return to their preview.
    redirectTo: new URL('/auth/callback', url).href,
    // Supabase always asks Google for email and profile, so openid makes the three scopes.
    scopes: 'openid',
    // hd steers Google's account chooser to school accounts. Nothing trusts it (ADR-005).
    queryParams: { hd: domain, prompt: 'select_account' },
  };
}

/** Why sign-in didn't finish, as the landing page's `error` parameter. */
export type SignInError = 'cancelled' | 'failed';

const SIGN_IN_ERROR_MESSAGES: Record<SignInError, string> = {
  cancelled: "You didn't finish signing in with Google. Try again when you're ready.",
  failed: "Google sign-in didn't work this time. Please try again.",
};

/** The landing page's message for its `error` parameter, or null when there's no error. */
export function signInErrorMessage(error: string | null): string | null {
  if (error === null) return null;
  return error === 'cancelled' ? SIGN_IN_ERROR_MESSAGES.cancelled : SIGN_IN_ERROR_MESSAGES.failed;
}

/** The landing page with a message, keeping the page to return to after another try. */
export function signInErrorPath(error: SignInError, next: string): string {
  return withNext(`/?error=${error}`, next);
}

/**
 * Why Supabase sent someone back to /auth/callback without a code. When the byui.edu hook rejects
 * a new account, Supabase passes on the hook's message, which names the domain. Google says
 * access_denied when someone cancels.
 */
export function callbackFailure(
  params: URLSearchParams,
  domain: string
): SignInError | 'not-eligible' {
  if (params.get('error_description')?.includes(domain)) return 'not-eligible';
  return params.get('error') === 'access_denied' ? 'cancelled' : 'failed';
}

/** Where to go after signing in. New members see Welcome first, which sends them on to `next`. */
export function afterSignInPath(isNewMember: boolean, next: string): string {
  return isNewMember ? withNext('/welcome', next) : next;
}

// Apps whose built-in browsers Google refuses to sign in from: Facebook and Messenger,
// Instagram, LinkedIn, Snapchat, TikTok, WeChat and LINE, and any Android app's WebView.
const IN_APP_BROWSER =
  /\bFBA[NV]\/|\bFB_IAB\b|\bInstagram\b|\bLinkedInApp\b|\bSnapchat\b|\bmusical_ly\b|\bBytedanceWebview\b|\bMicroMessenger\/|\bLine\/|; wv\)/;

/** True for the user agent of an app's built-in browser, which Google sign-in may block. */
export function isInAppBrowser(userAgent: string | null): boolean {
  return !!userAgent && IN_APP_BROWSER.test(userAgent);
}
