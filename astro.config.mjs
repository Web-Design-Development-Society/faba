// @ts-check
import { defineConfig, envField } from 'astro/config';

import cloudflare from '@astrojs/cloudflare';

// https://astro.build/config
export default defineConfig({
  // Pages render on demand unless they opt in to prerendering (ADR-001).
  output: 'server',
  // Prerendered pages are written as about.html rather than about/index.html, so Cloudflare serves
  // them at /about instead of redirecting to /about/ (INFO-01).
  build: { format: 'file' },
  // One Cloudflare Worker runs the whole app (ADR-002, ADR-014).
  adapter: cloudflare({
    // FABA has no image transforms.
    imageService: 'passthrough',
  }),
  // Supabase cookies hold the session, so Astro sessions and their KV namespace aren't needed.
  session: false,
  prefetch: true,
  // New activity can carry a picture (MEDIA-02): up to 2 MB, with its small and medium copies,
  // which Astro's 1 MB limit for an Action's form would refuse.
  security: { actionBodySizeLimit: 3 * 1024 * 1024 },
  env: {
    // Secrets are checked when src/middleware.ts imports astro:env/server, on every request, so a
    // missing or malformed one fails every page. That's why each secret is optional and has no
    // format check: the code that uses it checks it. Checking them at build time too would break CI
    // builds, which have no secrets.
    validateSecrets: false,
    // Every variable FABA reads. Non-secret values live in wrangler.jsonc, and secrets in
    // .dev.vars locally (see .dev.vars.example).
    schema: {
      SITE_URL: envField.string({ context: 'server', access: 'public', url: true }),
      SUPABASE_URL: envField.string({ context: 'server', access: 'public', url: true }),
      SUPABASE_PUBLISHABLE_KEY: envField.string({
        context: 'server',
        access: 'public',
        startsWith: 'sb_publishable_',
      }),
      // Optional, because astro:env/server reads every required secret when it loads, and
      // building the prerendered public pages (INFO-01) has no secrets. Only account deletion
      // uses it, and src/lib/server/secret-key.ts checks that it starts with sb_secret_.
      SUPABASE_SECRET_KEY: envField.string({ context: 'server', access: 'secret', optional: true }),
      ALLOWED_EMAIL_DOMAIN: envField.string({ context: 'server', access: 'public' }),
      LOG_LEVEL: envField.enum({
        context: 'server',
        access: 'public',
        values: ['debug', 'info', 'warn', 'error'],
        default: 'info',
      }),
      // Staging and production only.
      SENTRY_DSN: envField.string({ context: 'server', access: 'secret', optional: true }),
      // Web Push (NOTIF-20). Push is off in an environment without both. The Cron Trigger's
      // sender reads them from the Worker's environment (src/lib/server/push/send.ts).
      VAPID_PUBLIC_KEY: envField.string({ context: 'server', access: 'public', optional: true }),
      VAPID_PRIVATE_KEY: envField.string({ context: 'server', access: 'secret', optional: true }),
    },
  },
});
