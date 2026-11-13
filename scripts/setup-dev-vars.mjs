// Writes .dev.vars from .dev.vars.example, filling in the local Supabase secret key and a new Web
// Push key pair for this machine (NOTIF-20).
// Run after `npx supabase start`: npm run setup:dev-vars (add -- --force to overwrite).
import { execSync } from 'node:child_process';
import { existsSync, readFileSync, writeFileSync } from 'node:fs';
import { join } from 'node:path';

const root = join(import.meta.dirname, '..');
const target = join(root, '.dev.vars');

if (existsSync(target) && !process.argv.includes('--force')) {
  console.error('.dev.vars already exists. Run with -- --force to overwrite it.');
  process.exit(1);
}

let status;
try {
  status = execSync('npx supabase status -o env', { cwd: root, encoding: 'utf8' });
} catch {
  console.error('Could not read the local Supabase status. Is it running? Try: npx supabase start');
  process.exit(1);
}

const secretKey = status.match(/^SECRET_KEY="?([^"\n]+)"?$/m)?.[1];
if (!secretKey) {
  console.error('`npx supabase status -o env` printed no SECRET_KEY.');
  process.exit(1);
}

// The same as `npm run push:keys`, for this machine only.
const pair = await crypto.subtle.generateKey({ name: 'ECDSA', namedCurve: 'P-256' }, true, [
  'sign',
  'verify',
]);
const publicKey = Buffer.from(await crypto.subtle.exportKey('raw', pair.publicKey)).toString(
  'base64url'
);
const { d: privateKey } = await crypto.subtle.exportKey('jwk', pair.privateKey);

const example = readFileSync(join(root, '.dev.vars.example'), 'utf8');
writeFileSync(
  target,
  example
    .replace(/^SUPABASE_SECRET_KEY=.*$/m, `SUPABASE_SECRET_KEY=${secretKey}`)
    .replace(/^VAPID_PUBLIC_KEY=.*$/m, `VAPID_PUBLIC_KEY=${publicKey}`)
    .replace(/^VAPID_PRIVATE_KEY=.*$/m, `VAPID_PRIVATE_KEY=${privateKey}`)
);
console.log('Wrote .dev.vars with the local Supabase secret key and Web Push keys.');
