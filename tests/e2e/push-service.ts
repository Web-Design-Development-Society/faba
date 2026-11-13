// A stand-in push service for the Web Push tests (NOTIF-20). It plays a device: it has its own keys,
// takes the pushes the Worker posts to it, and decrypts them the way a browser would (RFC 8291).
import { createServer } from 'node:http';
import type { AddressInfo } from 'node:net';
import { base64url, fromBase64url } from '../../src/lib/server/push/webpush';

const encoder = new TextEncoder();

async function hkdf(salt: Uint8Array, ikm: Uint8Array, info: Uint8Array, length: number) {
  const key = await crypto.subtle.importKey('raw', ikm as BufferSource, 'HKDF', false, [
    'deriveBits',
  ]);
  const bits = await crypto.subtle.deriveBits(
    { name: 'HKDF', hash: 'SHA-256', salt: salt as BufferSource, info: info as BufferSource },
    key,
    length * 8
  );
  return new Uint8Array(bits);
}

/** A device's keys: its subscription's p256dh and auth, and the private key only it knows. */
export type DeviceKeys = { privateKey: string; p256dh: string; auth: string };

/** Reads a push the way the device's browser would. */
export async function decrypt(body: Uint8Array, device: DeviceKeys): Promise<Uint8Array> {
  const salt = body.slice(0, 16);
  const idLength = body[20];
  const serverKey = body.slice(21, 21 + idLength);
  const sealed = body.slice(21 + idLength);
  const deviceKey = fromBase64url(device.p256dh);

  const algorithm = { name: 'ECDH', namedCurve: 'P-256' };
  const mine = await crypto.subtle.importKey(
    'jwk',
    {
      kty: 'EC',
      crv: 'P-256',
      d: device.privateKey,
      x: base64url(deviceKey.slice(1, 33)),
      y: base64url(deviceKey.slice(33, 65)),
    },
    algorithm,
    false,
    ['deriveBits']
  );
  const theirs = await crypto.subtle.importKey('raw', serverKey, algorithm, false, []);
  const shared = new Uint8Array(
    await crypto.subtle.deriveBits({ name: 'ECDH', public: theirs }, mine, 256)
  );
  const info = new Uint8Array([...encoder.encode('WebPush: info\0'), ...deviceKey, ...serverKey]);
  const ikm = await hkdf(fromBase64url(device.auth), shared, info, 32);
  const cek = await hkdf(salt, ikm, encoder.encode('Content-Encoding: aes128gcm\0'), 16);
  const nonce = await hkdf(salt, ikm, encoder.encode('Content-Encoding: nonce\0'), 12);
  const key = await crypto.subtle.importKey('raw', cek, 'AES-GCM', false, ['decrypt']);
  const record = new Uint8Array(
    await crypto.subtle.decrypt({ name: 'AES-GCM', iv: nonce }, key, sealed)
  );
  // The record ends with 0x02, then any padding of zeros.
  let end = record.length - 1;
  while (end >= 0 && record[end] === 0) end--;
  if (record[end] !== 2) throw new Error('The push has no end-of-message mark.');
  return record.slice(0, end);
}

/** New keys for a made-up device whose pushes go to `endpoint`. */
export async function makeDevice(endpoint: string): Promise<DeviceKeys & { endpoint: string }> {
  const pair = (await crypto.subtle.generateKey({ name: 'ECDH', namedCurve: 'P-256' }, true, [
    'deriveBits',
  ])) as CryptoKeyPair;
  const jwk = await crypto.subtle.exportKey('jwk', pair.privateKey);
  return {
    endpoint,
    privateKey: jwk.d!,
    p256dh: base64url(new Uint8Array(await crypto.subtle.exportKey('raw', pair.publicKey))),
    auth: base64url(crypto.getRandomValues(new Uint8Array(16))),
  };
}

/** One push as the service received it. */
export type Received = { path: string; headers: Record<string, string>; body: Uint8Array };

/** Starts the stand-in push service on a free port, answering every push with `status`. */
export async function startPushService(status = 201) {
  const received: Received[] = [];
  const server = createServer((request, response) => {
    const chunks: Buffer[] = [];
    request.on('data', (chunk: Buffer) => chunks.push(chunk));
    request.on('end', () => {
      received.push({
        path: request.url ?? '',
        headers: Object.fromEntries(
          Object.entries(request.headers).map(([name, value]) => [name, String(value)])
        ),
        body: new Uint8Array(Buffer.concat(chunks)),
      });
      response.writeHead(status).end();
    });
  });
  await new Promise<void>((resolve) => server.listen(0, '127.0.0.1', resolve));
  const { port } = server.address() as AddressInfo;
  return {
    url: `http://127.0.0.1:${port}`,
    received,
    close: () => new Promise<void>((resolve) => server.close(() => resolve())),
  };
}
