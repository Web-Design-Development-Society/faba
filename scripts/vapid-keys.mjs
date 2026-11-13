// Makes a new Web Push key pair for an environment (NOTIF-20): npm run push:keys
// The public key goes in that environment's vars in wrangler.jsonc, as VAPID_PUBLIC_KEY. The
// private key is a secret: `npx wrangler secret put VAPID_PRIVATE_KEY --env <environment>`, then
// paste it. Changing an environment's keys stops pushes to every device turned on with the old
// ones, until each member turns push on again.
const pair = await crypto.subtle.generateKey({ name: 'ECDSA', namedCurve: 'P-256' }, true, [
  'sign',
  'verify',
]);
const publicKey = Buffer.from(await crypto.subtle.exportKey('raw', pair.publicKey)).toString(
  'base64url'
);
const { d } = await crypto.subtle.exportKey('jwk', pair.privateKey);

console.log(`VAPID_PUBLIC_KEY=${publicKey}`);
console.log(`VAPID_PRIVATE_KEY=${d}`);
