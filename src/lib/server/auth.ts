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
export function isAllowedEmail(email: string | null | undefined, domain: string): boolean {
  if (!email) return false;
  const at = email.indexOf('@');
  return (
    at > 0 &&
    at === email.lastIndexOf('@') &&
    email.slice(at + 1).toLowerCase() === domain.toLowerCase()
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

/**
 * Options for every auth cookie. Page scripts can't read them, and they're sent only over HTTPS
 * when the site uses it, which localhost doesn't.
 */
export function authCookieOptions(url: URL) {
  return {
    httpOnly: true,
    secure: url.protocol === 'https:',
    sameSite: 'lax',
    path: '/',
  } as const;
}
