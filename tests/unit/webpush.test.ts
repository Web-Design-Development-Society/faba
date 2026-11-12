// Web Push (NOTIF-20): encryption matches RFC 8291's worked example, the VAPID token verifies with
// FABA's public key, and only the browsers' push services are sent to.
import { describe, expect, it } from 'vitest';
import {
  base64url,
  encrypt,
  fromBase64url,
  isPushService,
  vapidAuthorization,
} from '../../src/lib/server/push/webpush';
import { decrypt } from '../e2e/push-service';

// RFC 8291, section 5.
const RFC = {
  plaintext: 'When I grow up, I want to be a watermelon',
  serverPrivate: 'yfWPiYE-n46HLnH0KqZOF1fJJU3MYrct3AELtAQ-oRw',
  serverPublic:
    'BP4z9KsN6nGRTbVYI_c7VJSPQTBtkgcy27mlmlMoZIIgDll6e3vCYLocInmYWAmS6TlzAC8wEqKK6PBru3jl7A8',
  devicePrivate: 'q1dXpw3UpT5VOmu_cf_v6ih07Aems3njxI-JWgLcM94',
  devicePublic:
    'BCVxsr7N_eNgVRqvHtD0zTZsEc6-VV-JvLexhqUzORcxaOzi6-AYWXvTBHm4bjyPjs7Vd8pZGH6SRpkNtoIAiw4',
  auth: 'BTBZMqHH6r4Tts7J_aSIgg',
  salt: 'DGv6ra1nlYgDCS1FRnbzlw',
  body: 'DGv6ra1nlYgDCS1FRnbzlwAAEABBBP4z9KsN6nGRTbVYI_c7VJSPQTBtkgcy27mlmlMoZIIgDll6e3vCYLocInmYWAmS6TlzAC8wEqKK6PBru3jl7A_yl95bQpu6cVPTpK4Mqgkf1CXztLVBSt2Ks3oZwbuwXPXLWyouBWLVWGNWQexSgSxsj_Qulcy4a-fN',
};

/** An ECDH key pair from a base64url private key and its public key. */
async function keyPair(privateKey: string, publicKey: string): Promise<CryptoKeyPair> {
  const point = fromBase64url(publicKey);
  const x = base64url(point.slice(1, 33));
  const y = base64url(point.slice(33, 65));
  const algorithm = { name: 'ECDH', namedCurve: 'P-256' };
  return {
    privateKey: await crypto.subtle.importKey(
      'jwk',
      { kty: 'EC', crv: 'P-256', d: privateKey, x, y },
      algorithm,
      false,
      ['deriveBits']
    ),
    publicKey: await crypto.subtle.importKey('raw', point, algorithm, true, []),
  };
}

describe('encrypt', () => {
  it('matches the example in RFC 8291', async () => {
    const body = await encrypt(
      new TextEncoder().encode(RFC.plaintext),
      { p256dh: RFC.devicePublic, auth: RFC.auth },
      { salt: fromBase64url(RFC.salt), keys: await keyPair(RFC.serverPrivate, RFC.serverPublic) }
    );
    expect(base64url(body)).toBe(RFC.body);
  });

  it('makes a push the device can read, with a new key and salt each time', async () => {
    const device = { p256dh: RFC.devicePublic, auth: RFC.auth };
    const message = new TextEncoder().encode('{"title":"Hike"}');
    const first = await encrypt(message, device);
    const second = await encrypt(message, device);
    expect(base64url(first)).not.toBe(base64url(second));
    const read = await decrypt(first, { privateKey: RFC.devicePrivate, ...device });
    expect(new TextDecoder().decode(read)).toBe('{"title":"Hike"}');
  });

  it('refuses a message too long for one record', async () => {
    const device = { p256dh: RFC.devicePublic, auth: RFC.auth };
    await expect(encrypt(new Uint8Array(3001), device)).rejects.toThrow('at most 3000 bytes');
  });
});

describe('vapidAuthorization', () => {
  it('signs a token for the push service that FABA’s public key verifies', async () => {
    const pair = (await crypto.subtle.generateKey({ name: 'ECDSA', namedCurve: 'P-256' }, true, [
      'sign',
      'verify',
    ])) as CryptoKeyPair;
    const jwk = await crypto.subtle.exportKey('jwk', pair.privateKey);
    const publicKey = base64url(
      new Uint8Array(await crypto.subtle.exportKey('raw', pair.publicKey))
    );
    const now = new Date('2026-12-04T19:00:00Z');

    const header = await vapidAuthorization(
      'https://fcm.googleapis.com/fcm/send/abc',
      { publicKey, privateKey: jwk.d!, subject: 'https://faba.example' },
      now
    );

    const [, token, key] = header.match(/^vapid t=([^,]+), k=(.+)$/)!;
    expect(key).toBe(publicKey);
    const [head, claims, signature] = token.split('.');
    expect(JSON.parse(new TextDecoder().decode(fromBase64url(head)))).toEqual({
      typ: 'JWT',
      alg: 'ES256',
    });
    expect(JSON.parse(new TextDecoder().decode(fromBase64url(claims)))).toEqual({
      aud: 'https://fcm.googleapis.com',
      exp: now.getTime() / 1000 + 12 * 60 * 60,
      sub: 'https://faba.example',
    });
    const verified = await crypto.subtle.verify(
      { name: 'ECDSA', hash: 'SHA-256' },
      pair.publicKey,
      fromBase64url(signature),
      new TextEncoder().encode(`${head}.${claims}`)
    );
    expect(verified).toBe(true);
  });
});

describe('isPushService', () => {
  it('sends to the browsers’ push services over HTTPS', () => {
    for (const endpoint of [
      'https://fcm.googleapis.com/fcm/send/abc',
      'https://updates.push.services.mozilla.com/wpush/v2/abc',
      'https://web.push.apple.com/QGuQ',
      'https://wns2-par02p.notify.windows.com/w/?token=abc',
    ]) {
      expect(isPushService(endpoint)).toBe(true);
    }
  });

  it('refuses anywhere else, and plain HTTP', () => {
    for (const endpoint of [
      'http://fcm.googleapis.com/fcm/send/abc',
      'https://example.com/push',
      'https://fcm.googleapis.com.example.com/x',
      'https://evilpush.apple.com.example/x',
      'not a url',
    ]) {
      expect(isPushService(endpoint)).toBe(false);
    }
  });

  it('allows the stand-in push service on localhost only on a developer’s machine', () => {
    expect(isPushService('http://127.0.0.1:9000/push/1')).toBe(false);
    expect(isPushService('http://127.0.0.1:9000/push/1', true)).toBe(true);
  });
});
