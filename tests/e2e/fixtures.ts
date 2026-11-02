// Shared setup for the end-to-end tests: signing in as a seeded persona or a new member, and the
// axe check.
import { readFileSync } from 'node:fs';
import AxeBuilder from '@axe-core/playwright';
import { test as base, expect, type BrowserContext, type Page } from '@playwright/test';
import { createServerClient } from '@supabase/ssr';
import { createClient } from '@supabase/supabase-js';

export { expect };

// Local Supabase, as in wrangler.jsonc.
export const SUPABASE_URL = 'http://127.0.0.1:54331';
export const SUPABASE_PUBLISHABLE_KEY = 'sb_publishable_ACJWlzQHlZjBrEguHvfOxg_3BJgxAaH';

// The personas in supabase/seed/local_accounts.sql, which all share this password.
const PERSONAS = {
  member: 'member.test@byui.edu',
  organizer: 'organizer.test@byui.edu',
  moderator: 'moderator.test@byui.edu',
  admin: 'admin.test@byui.edu',
  suspended: 'suspended.test@byui.edu',
};
const PASSWORD = 'faba-local-dev';

export type Persona = keyof typeof PERSONAS;

export const test = base.extend<{
  /** Signs this test's browser in as a persona, skipping Google. */
  signInAs: (persona: Persona) => Promise<void>;
  /** Signs in as a new byui.edu account that hasn't been through Welcome, deleted afterwards. */
  newMember: { displayName: string };
}>({
  signInAs: async ({ context, baseURL }, use) => {
    await use((persona) => signIn(context, baseURL!, PERSONAS[persona]));
  },
  newMember: async ({ context, baseURL }, use) => {
    // Creating and deleting accounts needs the local secret key, which setup:dev-vars writes.
    const secretKey = readFileSync('.dev.vars', 'utf8').match(/^SUPABASE_SECRET_KEY=(\S+)/m)?.[1];
    if (!secretKey) throw new Error('.dev.vars has no SUPABASE_SECRET_KEY. Run setup:dev-vars.');
    const admin = createClient(SUPABASE_URL, secretKey, { auth: { persistSession: false } });

    const displayName = 'Nia Newcomer';
    const email = `new.${crypto.randomUUID()}@byui.edu`;
    const { data, error } = await admin.auth.admin.createUser({
      email,
      password: PASSWORD,
      email_confirm: true,
      // A grey square instead of a Google photo, so the tests stay offline.
      user_metadata: { full_name: displayName, avatar_url: GREY_SQUARE },
    });
    if (error) throw new Error(`Creating ${email} failed: ${error.message}`);
    try {
      await signIn(context, baseURL!, email);
      await use({ displayName });
    } finally {
      await admin.auth.admin.deleteUser(data.user.id);
    }
  },
});

const GREY_SQUARE =
  "data:image/svg+xml,<svg xmlns='http://www.w3.org/2000/svg' viewBox='0 0 1 1'><rect width='1' height='1' fill='grey'/></svg>";

/**
 * A password sign-in through @supabase/ssr, which writes the session cookies in the same format as
 * the app. They go to the browser instead of a response.
 */
async function signIn(context: BrowserContext, baseURL: string, email: string) {
  const cookies: { name: string; value: string }[] = [];
  const supabase = createServerClient(SUPABASE_URL, SUPABASE_PUBLISHABLE_KEY, {
    cookies: { getAll: () => [], setAll: (toSet) => void cookies.push(...toSet) },
  });
  const { error } = await supabase.auth.signInWithPassword({ email, password: PASSWORD });
  if (error) {
    throw new Error(`Signing in as ${email} failed. Is local Supabase seeded? ${error.message}`);
  }
  await context.addCookies(
    cookies.map(({ name, value }) => ({
      name,
      value,
      url: baseURL,
      httpOnly: true,
      sameSite: 'Lax' as const,
    }))
  );
}

/** Fails the test if axe finds a serious or critical problem on the page as it is now. */
export async function expectAccessible(page: Page) {
  const { violations } = await new AxeBuilder({ page }).analyze();
  const problems = violations
    .filter(({ impact }) => impact === 'serious' || impact === 'critical')
    .map(
      ({ id, impact, help, nodes }) =>
        `${id} (${impact}): ${help} at ${nodes.map((node) => node.target).join(', ')}`
    );
  expect(problems, `axe found problems on ${page.url()}`).toEqual([]);
}
