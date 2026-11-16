// The lint rules that keep pages on the request client (OPS-04, design document section 9.6), run
// through ESLint's Node API on code as if it were at the paths that matter. Two blocks that set the
// same rule once replaced each other, so one limit quietly checked a single file.
import { ESLint } from 'eslint';
import { fileURLToPath } from 'node:url';
import { describe, expect, it } from 'vitest';

const eslint = new ESLint({ cwd: fileURLToPath(new URL('../..', import.meta.url)) });

const CREATE_CLIENT = `import { createClient } from '@supabase/supabase-js';
export const make = createClient;
`;
const ADMIN = `import { admin } from '../lib/server/admin';
export const client = admin;
`;
const TYPE_ONLY = `import type { SupabaseClient } from '@supabase/supabase-js';
export type Client = SupabaseClient;
`;

const USE_REQUEST_CLIENT = 'Use the request client from src/lib/server/supabase.ts.';
const ONLY_DELETION = 'Only the account-deletion Action may use the secret-key client.';

/** What the import rule says about `code` at `filePath`, as the end of each message. */
async function restricted(code: string, filePath: string) {
  const text = filePath.endsWith('.astro') ? `---\n${code}---\n\n<p>Hello</p>\n` : code;
  const [result] = await eslint.lintText(text, { filePath });
  return result.messages
    .filter((message) => message.ruleId === 'no-restricted-imports')
    .map((message) => (message.message.includes(USE_REQUEST_CLIENT) ? 'createClient' : 'admin'));
}

describe('the Supabase client import rules', { timeout: 30_000 }, () => {
  it.each([
    'src/pages/discover.ts',
    'src/pages/api/media/upload.ts',
    'src/actions/activities.ts',
    'src/components/Card.astro',
    'src/middleware.ts',
    'src/actions/profile.ts',
  ])('createClient from supabase-js is an error in %s', async (path) => {
    expect(await restricted(CREATE_CLIENT, path)).toEqual(['createClient']);
  });

  it.each(['src/lib/server/admin.ts', 'src/lib/server/push/send.ts', 'tests/e2e/fixtures.ts'])(
    'but not in %s',
    async (path) => {
      expect(await restricted(CREATE_CLIENT, path)).toEqual([]);
    }
  );

  it.each([
    'src/pages/discover.ts',
    'src/actions/activities.ts',
    'src/components/Card.astro',
    'src/lib/server/push/send.ts',
  ])('the secret-key client is an error in %s', async (path) => {
    expect(await restricted(ADMIN, path)).toEqual(['admin']);
  });

  it.each(['src/actions/profile.ts', 'tests/e2e/fixtures.ts'])('but not in %s', async (path) => {
    expect(await restricted(ADMIN, path)).toEqual([]);
  });

  it('a file both apply to gets both', async () => {
    expect(await restricted(CREATE_CLIENT + ADMIN, 'src/pages/discover.ts')).toEqual([
      'createClient',
      'admin',
    ]);
  });

  it('a type import is fine', async () => {
    expect(await restricted(TYPE_ONLY, 'src/pages/discover.ts')).toEqual([]);
  });

  it('says what to do instead', async () => {
    const [result] = await eslint.lintText(CREATE_CLIENT + ADMIN, {
      filePath: 'src/pages/discover.ts',
    });
    const messages = result.messages.map((message) => message.message).join('\n');
    expect(messages).toContain(USE_REQUEST_CLIENT);
    expect(messages).toContain(ONLY_DELETION);
  });
});
