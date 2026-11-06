// @ts-check
import js from '@eslint/js';
import astro from 'eslint-plugin-astro';
import { defineConfig, globalIgnores } from 'eslint/config';
import globals from 'globals';
import tseslint from 'typescript-eslint';

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
    // The secret key bypasses Row Level Security, so only account deletion uses it (PROF-05,
    // design document section 9.6).
    files: ['src/**/*.{ts,astro}'],
    ignores: ['src/actions/profile.ts'],
    rules: {
      'no-restricted-imports': [
        'error',
        {
          patterns: [
            {
              group: ['**/server/admin', '**/server/admin.ts'],
              message: 'Only the account-deletion Action may use the secret-key client.',
            },
          ],
        },
      ],
    },
  }
);
