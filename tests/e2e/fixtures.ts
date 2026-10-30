// Shared setup for the end-to-end tests: signing in as a seeded persona, and the axe check.
import AxeBuilder from '@axe-core/playwright';
import { test as base, expect, type Page } from '@playwright/test';
import { createServerClient } from '@supabase/ssr';

export { expect };

// Local Supabase, as in wrangler.jsonc.
export const SUPABASE_URL = 'http://127.0.0.1:54331';
const SUPABASE_PUBLISHABLE_KEY = 'sb_publishable_ACJWlzQHlZjBrEguHvfOxg_3BJgxAaH';

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
}>({
  signInAs: async ({ context, baseURL }, use) => {
    await use(async (persona) => {
      // A password sign-in through @supabase/ssr, which writes the session cookies in the same
      // format as the app. They go to the browser instead of a response.
      const cookies: { name: string; value: string }[] = [];
      const supabase = createServerClient(SUPABASE_URL, SUPABASE_PUBLISHABLE_KEY, {
        cookies: { getAll: () => [], setAll: (toSet) => void cookies.push(...toSet) },
      });
      const { error } = await supabase.auth.signInWithPassword({
        email: PERSONAS[persona],
        password: PASSWORD,
      });
      if (error) {
        throw new Error(
          `Signing in as ${persona} failed. Is local Supabase seeded? ${error.message}`
        );
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
    });
  },
});

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
