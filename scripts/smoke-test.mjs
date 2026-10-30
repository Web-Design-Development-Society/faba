// Checks that a deployed FABA responds (FND-08, design document section 11.7).
// Usage: node scripts/smoke-test.mjs [url]. Without a URL, it checks SITE_URL from the last build.
// None of the checks signs in.
import { readFileSync } from 'node:fs';
import { join } from 'node:path';

const root = join(import.meta.dirname, '..');
const baseUrl =
  process.argv[2] ??
  JSON.parse(readFileSync(join(root, 'dist/server/wrangler.json'), 'utf8')).vars.SITE_URL;

// A new deploy can take a few seconds to reach every Cloudflare location.
const attempts = 6;
const delayMs = 10_000;

const checks = [
  {
    name: 'the landing page loads',
    path: '/',
    test: (response) =>
      response.status === 200 && response.headers.get('content-type')?.includes('text/html'),
  },
  {
    name: 'the health endpoint returns OK',
    path: '/api/health',
    test: async (response) => response.status === 200 && (await response.json()).status === 'ok',
  },
  {
    name: 'a page for members redirects to sign-in',
    path: '/discover',
    test: (response) => response.status === 302 && location(response)?.pathname === '/auth/login',
  },
  {
    name: 'signing in redirects to Google through Supabase',
    path: '/auth/login',
    init: {
      method: 'POST',
      // Astro refuses form posts from other sites, so this one says it comes from FABA.
      headers: {
        origin: new URL(baseUrl).origin,
        'content-type': 'application/x-www-form-urlencoded',
      },
      body: 'next=%2Fdiscover',
    },
    test: (response) => {
      const target = location(response);
      return (
        response.status === 303 &&
        target?.pathname === '/auth/v1/authorize' &&
        target.searchParams.get('provider') === 'google'
      );
    },
  },
];

function location(response) {
  const value = response.headers.get('location');
  return value ? new URL(value, response.url) : undefined;
}

let failed = false;
for (const check of checks) {
  const url = new URL(check.path, baseUrl);
  let result = 'no response';
  for (let attempt = 1; attempt <= attempts; attempt++) {
    try {
      const response = await fetch(url, { ...check.init, redirect: 'manual' });
      if (await check.test(response)) {
        result = 'ok';
        break;
      }
      result = `status ${response.status}`;
    } catch (error) {
      result = error.message;
    }
    if (attempt < attempts) await new Promise((resolve) => setTimeout(resolve, delayMs));
  }
  console.log(`${result === 'ok' ? '✓' : '✗'} ${check.name} (${url}): ${result}`);
  if (result !== 'ok') failed = true;
}

if (failed) {
  console.error('Smoke tests failed.');
  process.exit(1);
}
