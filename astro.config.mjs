// @ts-check
import { defineConfig, envField } from 'astro/config';

import cloudflare from '@astrojs/cloudflare';

// https://astro.build/config
export default defineConfig({
  // Pages render on demand unless they opt in to prerendering (ADR-001).
  output: 'server',
  // One Cloudflare Worker runs the whole app (ADR-002, ADR-014).
  adapter: cloudflare({
    // FABA has no image transforms.
    imageService: 'passthrough',
  }),
  // Supabase cookies hold the session, so Astro sessions and their KV namespace aren't needed.
  session: false,
  prefetch: true,
  env: {
    // Fail at startup, not on first use, when a variable is missing or invalid.
    validateSecrets: true,
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
      SUPABASE_SECRET_KEY: envField.string({
        context: 'server',
        access: 'secret',
        startsWith: 'sb_secret_',
      }),
      ALLOWED_EMAIL_DOMAIN: envField.string({ context: 'server', access: 'public' }),
      LOG_LEVEL: envField.enum({
        context: 'server',
        access: 'public',
        values: ['debug', 'info', 'warn', 'error'],
        default: 'info',
      }),
      // Staging and production only.
      SENTRY_DSN: envField.string({ context: 'server', access: 'secret', optional: true }),
    },
  },
});
