// Web Push with only the Web Crypto API, so it runs in the Worker with no dependency (NOTIF-20).
// VAPID (RFC 8292) signs that FABA sent a push, and aes128gcm (RFC 8291) encrypts it so only the
// member's device can read it. tests/unit/webpush.test.ts checks it against RFC 8291's example.

const encoder = new TextEncoder();

/** `bytes` as base64url without padding, as Web Push writes keys. */
export function base64url(bytes: Uint8Array): string {
  let binary = '';
  for (const byte of bytes) binary += String.fromCharCode(byte);
  return btoa(binary).replace(/\+/g, '-').replace(/\//g, '_').replace(/=+$/, '');
}

/** The bytes in base64url `text`, with or without padding. */
export function fromBase64url(text: string): Uint8Array<ArrayBuffer> {
  const binary = atob(text.replace(/-/g, '+').replace(/_/g, '/'));
  const bytes = new Uint8Array(binary.length);
  for (let i = 0; i < binary.length; i++) bytes[i] = binary.charCodeAt(i);
  return bytes;
}

function concat(...parts: Uint8Array[]): Uint8Array<ArrayBuffer> {
  const out = new Uint8Array(parts.reduce((total, part) => total + part.length, 0));
  let at = 0;
  for (const part of parts) {
    out.set(part, at);
    at += part.length;
  }
  return out;
}

async function hkdf(
  salt: Uint8Array<ArrayBuffer>,
  ikm: Uint8Array<ArrayBuffer>,
  info: Uint8Array<ArrayBuffer>,
  length: number
): Promise<Uint8Array<ArrayBuffer>> {
  const key = await crypto.subtle.importKey('raw', ikm, 'HKDF', false, ['deriveBits']);
  const bits = await crypto.subtle.deriveBits(
    { name: 'HKDF', hash: 'SHA-256', salt, info },
    key,
    length * 8
  );
  return new Uint8Array(bits);
}

/** A device's push subscription, as the browser gives it and push_subscriptions stores it. */
export type Subscription = { endpoint: string; p256dh: string; auth: string };

/** FABA's VAPID keys, base64url: the 65-byte public key and the 32-byte private key. */
export type Vapid = { publicKey: string; privateKey: string; subject: string };

/** The record size FABA writes. A message must fit in one record, so it's under 4,000 bytes. */
const RECORD_SIZE = 4096;

/** The longest message FABA sends, comfortably inside one record and every push service's limit. */
export const MAX_MESSAGE = 3000;

/**
 * Encrypts `message` for one device (RFC 8291). Each push gets a new key pair and salt. Tests pass
 * fixed ones in `fixed` to match the RFC's example.
 */
export async function encrypt(
  message: Uint8Array,
  { p256dh, auth }: Pick<Subscription, 'p256dh' | 'auth'>,
  fixed: { salt?: Uint8Array<ArrayBuffer>; keys?: CryptoKeyPair } = {}
): Promise<Uint8Array<ArrayBuffer>> {
  if (message.length > MAX_MESSAGE) throw new Error(`A push is at most ${MAX_MESSAGE} bytes.`);
  const deviceKey = fromBase64url(p256dh);
  const secret = fromBase64url(auth);
  const salt = fixed.salt ?? crypto.getRandomValues(new Uint8Array(16));
  const keys =
    fixed.keys ??
    ((await crypto.subtle.generateKey({ name: 'ECDH', namedCurve: 'P-256' }, true, [
      'deriveBits',
    ])) as CryptoKeyPair);
  const serverKey = new Uint8Array(await crypto.subtle.exportKey('raw', keys.publicKey));

  const device = await crypto.subtle.importKey(
    'raw',
    deviceKey,
    { name: 'ECDH', namedCurve: 'P-256' },
    false,
    []
  );
  const shared = new Uint8Array(
    await crypto.subtle.deriveBits({ name: 'ECDH', public: device }, keys.privateKey, 256)
  );
  const ikm = await hkdf(
    secret,
    shared,
    concat(encoder.encode('WebPush: info\0'), deviceKey, serverKey),
    32
  );
  const cek = await hkdf(salt, ikm, encoder.encode('Content-Encoding: aes128gcm\0'), 16);
  const nonce = await hkdf(salt, ikm, encoder.encode('Content-Encoding: nonce\0'), 12);

  const key = await crypto.subtle.importKey('raw', cek, 'AES-GCM', false, ['encrypt']);
  // One record: the message, then 0x02, which marks the last record (RFC 8188).
  const sealed = new Uint8Array(
    await crypto.subtle.encrypt(
      { name: 'AES-GCM', iv: nonce },
      key,
      concat(message, Uint8Array.of(2))
    )
  );

  // The header: the salt, the record size, and the server's public key for this push.
  const header = new Uint8Array(16 + 4 + 1 + serverKey.length);
  header.set(salt, 0);
  new DataView(header.buffer).setUint32(16, RECORD_SIZE);
  header[20] = serverKey.length;
  header.set(serverKey, 21);
  return concat(header, sealed);
}

/**
 * The Authorization header that tells the push service FABA sent this (RFC 8292): a token for the
 * endpoint's origin, signed with FABA's private key, good for 12 hours.
 */
export async function vapidAuthorization(
  endpoint: string,
  vapid: Vapid,
  now: Date = new Date()
): Promise<string> {
  const publicKey = fromBase64url(vapid.publicKey);
  const key = await crypto.subtle.importKey(
    'jwk',
    {
      kty: 'EC',
      crv: 'P-256',
      d: vapid.privateKey,
      x: base64url(publicKey.slice(1, 33)),
      y: base64url(publicKey.slice(33, 65)),
    },
    { name: 'ECDSA', namedCurve: 'P-256' },
    false,
    ['sign']
  );
  const part = (value: object) => base64url(encoder.encode(JSON.stringify(value)));
  const unsigned = `${part({ typ: 'JWT', alg: 'ES256' })}.${part({
    aud: new URL(endpoint).origin,
    exp: Math.floor(now.getTime() / 1000) + 12 * 60 * 60,
    sub: vapid.subject,
  })}`;
  // Web Crypto signs ECDSA as r and s side by side, which is what a JWT wants.
  const signature = new Uint8Array(
    await crypto.subtle.sign({ name: 'ECDSA', hash: 'SHA-256' }, key, encoder.encode(unsigned))
  );
  return `vapid t=${unsigned}.${base64url(signature)}, k=${vapid.publicKey}`;
}

/** The push services browsers use: Chrome and Android, Firefox, Safari, and Edge. */
const PUSH_SERVICES = [
  /^fcm\.googleapis\.com$/,
  /^updates\.push\.services\.mozilla\.com$/,
  /^([a-z0-9-]+\.)*push\.apple\.com$/,
  /^([a-z0-9-]+\.)*notify\.windows\.com$/,
];

/**
 * Whether FABA sends to `endpoint`: one of the browsers' push services over HTTPS, so a made-up
 * address can't make the Worker post somewhere else. On a developer's machine (`local`), the
 * end-to-end tests' stand-in push service on localhost too.
 */
export function isPushService(endpoint: string, local = false): boolean {
  let url: URL;
  try {
    url = new URL(endpoint);
  } catch {
    return false;
  }
  if (local && ['localhost', '127.0.0.1'].includes(url.hostname)) return true;
  return url.protocol === 'https:' && PUSH_SERVICES.some((service) => service.test(url.hostname));
}

/** How urgent a push is, for the push service: high wakes a phone right away. */
export type Urgency = 'high' | 'normal';

/**
 * Sends `message` to one device. `topic` replaces an earlier push with the same topic that the
 * device hasn't fetched yet. Returns the push service's response.
 */
export async function sendPush(
  subscription: Subscription,
  message: object,
  vapid: Vapid,
  options: { ttl: number; urgency: Urgency; topic?: string; fetch?: typeof fetch }
): Promise<Response> {
  const body = await encrypt(encoder.encode(JSON.stringify(message)), subscription);
  const headers: Record<string, string> = {
    Authorization: await vapidAuthorization(subscription.endpoint, vapid),
    TTL: String(options.ttl),
    Urgency: options.urgency,
    'Content-Encoding': 'aes128gcm',
    'Content-Type': 'application/octet-stream',
  };
  if (options.topic) headers.Topic = options.topic;
  return (options.fetch ?? fetch)(subscription.endpoint, { method: 'POST', headers, body });
}
