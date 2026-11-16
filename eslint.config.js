// @ts-check
import js from '@eslint/js';
import astro from 'eslint-plugin-astro';
import { defineConfig, globalIgnores } from 'eslint/config';
import globals from 'globals';
import tseslint from 'typescript-eslint';

/** A client made with supabase-js, not @supabase/ssr, is one with the secret key. */
const CREATE_CLIENT = {
  name: '@supabase/supabase-js',
  importNames: ['createClient'],
  message: 'Use the request client from src/lib/server/supabase.ts.',
};

/** The secret key bypasses Row Level Security, so only account deletion may use it (PROF-05). */
const ADMIN = {
  group: ['**/server/admin', '**/server/admin.ts'],
  message: 'Only the account-deletion Action may use the secret-key client.',
};

// The recommended rules for JavaScript, TypeScript and Astro components (FND-07).
export default defineConfig(
  globalIgnores(['dist/', '.astro/', '.wrangler/', 'playwright-report/', 'test-results/']),
  js.configs.recommended,
  tseslint.configs.recommended,
  astro.configs.recommended,
  {
    // Scripts and config files run in Node.
    files: ['**/*.{js,mjs,cjs}'],
    languageOptions: { globals: globals.node },
  },
  {
    // Two limits keep pages on the request client, which acts as the signed-in member and so obeys
    // Row Level Security (design document section 9.6). Both are in this one entry because in flat
    // config a later block's no-restricted-imports replaces an earlier one's rather than adding to
    // it (OPS-04). The two blocks after this one keep only the limit that applies to their files.
    files: ['src/**/*.{ts,astro}'],
    rules: { 'no-restricted-imports': ['error', { paths: [CREATE_CLIENT], patterns: [ADMIN] }] },
  },
  {
    // The two that need a client with the secret key make their own: admin.ts and the push sender
    // (NOTIF-20).
    files: ['src/lib/server/admin.ts', 'src/lib/server/push/send.ts'],
    rules: { 'no-restricted-imports': ['error', { patterns: [ADMIN] }] },
  },
  {
    // Only account deletion uses admin.ts (PROF-05).
    files: ['src/actions/profile.ts'],
    rules: { 'no-restricted-imports': ['error', { paths: [CREATE_CLIENT] }] },
  }
);
