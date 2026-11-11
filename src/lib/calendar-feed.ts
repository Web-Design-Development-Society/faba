// The secret link to a member's calendar feed (CAL-01). The token is random, shown once, and only
// its SHA-256 hash is stored. A calendar app reads the feed with the token in the link.

/** A new feed token: 32 random bytes, base64url, so it's safe in a link (43 characters). */
export function newFeedToken(): string {
  const bytes = crypto.getRandomValues(new Uint8Array(32));
  let binary = '';
  for (const byte of bytes) binary += String.fromCharCode(byte);
  return btoa(binary).replace(/\+/g, '-').replace(/\//g, '_').replace(/=+$/, '');
}

/** The hex SHA-256 of `token`, which is what the database stores and looks up. */
export async function hashFeedToken(token: string): Promise<string> {
  const digest = await crypto.subtle.digest('SHA-256', new TextEncoder().encode(token));
  return [...new Uint8Array(digest)].map((byte) => byte.toString(16).padStart(2, '0')).join('');
}
