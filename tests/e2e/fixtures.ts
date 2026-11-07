// Shared setup for the end-to-end tests: signing in as a seeded persona or a new member, and the
// axe check.
import { readFileSync } from 'node:fs';
import AxeBuilder from '@axe-core/playwright';
import { test as base, expect, type BrowserContext, type Page } from '@playwright/test';
import {
  combineChunks,
  createChunks,
  createServerClient,
  stringFromBase64URL,
  stringToBase64URL,
} from '@supabase/ssr';
import { createClient, type Session, type SupabaseClient } from '@supabase/supabase-js';
import type { Database } from '../../src/lib/db.types';

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

type NewActivity = Database['public']['Functions']['create_activity']['Args'];

export const test = base.extend<{
  /** Signs this test's browser in as a persona, skipping Google. */
  signInAs: (persona: Persona) => Promise<void>;
  /** Signs in as a new byui.edu account that hasn't been through Welcome, deleted afterwards. */
  newMember: { displayName: string };
  /**
   * Signs in as a new member who has accepted the guidelines, so the shared personas' activities
   * and daily limits stay as they are. `admin` sets up data for them. Their account and activities
   * are deleted afterwards.
   */
  poster: { id: string; admin: SupabaseClient };
  /**
   * A new member, Hana Host, who posts activities through create_activity() while the browser is
   * signed in as someone else. `post` makes a hike tomorrow unless told otherwise, and `admin`
   * changes it. Their account and activities are deleted afterwards.
   */
  host: {
    id: string;
    admin: SupabaseClient;
    post: (activity?: Partial<NewActivity>) => Promise<string>;
  };
  /**
   * `count` new members who have accepted the guidelines, each with a client signed in as them,
   * for many at once (RSVP-04). Their accounts are deleted afterwards.
   */
  crowd: (count: number) => Promise<SupabaseClient<Database>[]>;
}>({
  signInAs: async ({ context, baseURL }, use) => {
    await use((persona) => signIn(context, baseURL!, PERSONAS[persona]));
  },
  newMember: async ({ context, baseURL }, use) => {
    const admin = adminClient();
    const displayName = 'Nia Newcomer';
    const { id, email } = await createAccount(admin, displayName);
    try {
      await signIn(context, baseURL!, email);
      await use({ displayName });
    } finally {
      await admin.auth.admin.deleteUser(id);
    }
  },
  poster: async ({ context, baseURL }, use) => {
    const admin = adminClient();
    const { id, email } = await createAccount(admin, 'Pat Poster');
    try {
      await acceptGuidelines(admin, id);
      await signIn(context, baseURL!, email);
      await use({ id, admin });
    } finally {
      await deleteAccount(admin, id);
    }
  },
  // eslint-disable-next-line no-empty-pattern -- Playwright needs the object, and this uses nothing.
  host: async ({}, use) => {
    const admin = adminClient();
    const { id, email } = await createAccount(admin, 'Hana Host');
    try {
      await acceptGuidelines(admin, id);
      const host = createClient<Database>(SUPABASE_URL, SUPABASE_PUBLISHABLE_KEY, {
        auth: { persistSession: false },
      });
      const { error } = await host.auth.signInWithPassword({ email, password: PASSWORD });
      if (error) throw new Error(`Signing in as ${email} failed: ${error.message}`);
      const post = async (activity: Partial<NewActivity> = {}) => {
        const { data, error } = await host.rpc('create_activity', {
          title: 'Sunrise hike up the R',
          category_id: 'outdoors',
          starts_at: new Date(Date.now() + 24 * 60 * 60 * 1000).toISOString(),
          location_name: 'R Mountain trailhead',
          ...activity,
        });
        if (error) throw new Error(`Posting failed: ${error.message}`);
        return data;
      };
      await use({ id, admin, post });
    } finally {
      await deleteAccount(admin, id);
    }
  },
  // eslint-disable-next-line no-empty-pattern -- Playwright needs the object, and this uses nothing.
  crowd: async ({}, use) => {
    const admin = adminClient();
    const ids: string[] = [];
    try {
      await use((count) =>
        Promise.all(
          Array.from({ length: count }, async (_, n) => {
            const { id, email } = await createAccount(admin, `Crowd Member ${n + 1}`);
            ids.push(id);
            await acceptGuidelines(admin, id);
            const member = createClient<Database>(SUPABASE_URL, SUPABASE_PUBLISHABLE_KEY, {
              auth: { persistSession: false },
            });
            const { error } = await member.auth.signInWithPassword({ email, password: PASSWORD });
            if (error) throw new Error(`Signing in as ${email} failed: ${error.message}`);
            return member;
          })
        )
      );
    } finally {
      await Promise.all(ids.map((id) => deleteAccount(admin, id)));
    }
  },
});

/** A client with the local secret key, which setup:dev-vars writes. It bypasses RLS. */
function adminClient() {
  const secretKey = readFileSync('.dev.vars', 'utf8').match(/^SUPABASE_SECRET_KEY=(\S+)/m)?.[1];
  if (!secretKey) throw new Error('.dev.vars has no SUPABASE_SECRET_KEY. Run setup:dev-vars.');
  return createClient(SUPABASE_URL, secretKey, { auth: { persistSession: false } });
}

/** A new byui.edu account, whose profile the database makes. */
async function createAccount(admin: SupabaseClient, displayName: string) {
  const email = `new.${crypto.randomUUID()}@byui.edu`;
  const { data, error } = await admin.auth.admin.createUser({
    email,
    password: PASSWORD,
    email_confirm: true,
    // A grey square instead of a Google photo, so the tests stay offline.
    user_metadata: { full_name: displayName, avatar_url: GREY_SQUARE },
  });
  if (error) throw new Error(`Creating ${email} failed: ${error.message}`);
  return { id: data.user.id, email };
}

/** Skips Welcome for a new account. */
async function acceptGuidelines(admin: SupabaseClient, id: string) {
  await admin
    .from('profiles')
    .update({ guidelines_version: 1, guidelines_accepted_at: new Date().toISOString() })
    .eq('id', id);
}

/**
 * Deletes an account, its activities and its reports. Deleting only the account keeps them, with
 * no organizer or reporter.
 */
async function deleteAccount(admin: SupabaseClient, id: string) {
  await admin.from('activities').delete().eq('organizer_id', id);
  await admin.from('reports').delete().eq('reporter_id', id);
  await admin.auth.admin.deleteUser(id);
}

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

// @supabase/ssr stores the session as base64url JSON in a cookie named after the Supabase host, or
// in chunks named .0, .1 and so on when it's long.
const SESSION_KEY = `sb-${new URL(SUPABASE_URL).hostname.split('.')[0]}-auth-token`;
const BASE64_PREFIX = 'base64-';

/** The browser's Supabase session cookies. */
export async function sessionCookies(context: BrowserContext, baseURL: string) {
  return (await context.cookies(baseURL)).filter(
    ({ name }) => name === SESSION_KEY || name.startsWith(`${SESSION_KEY}.`)
  );
}

/** The Supabase session stored in the browser's cookies. */
export async function readSession(context: BrowserContext, baseURL: string): Promise<Session> {
  const cookies = await sessionCookies(context, baseURL);
  const stored = await combineChunks(SESSION_KEY, (n) => cookies.find((c) => c.name === n)?.value);
  if (!stored) throw new Error('The browser has no Supabase session.');
  return JSON.parse(stringFromBase64URL(stored.slice(BASE64_PREFIX.length)));
}

/** Replaces the browser's session cookies with `session`. */
export async function writeSession(context: BrowserContext, baseURL: string, session: Session) {
  for (const { name } of await sessionCookies(context, baseURL)) {
    await context.clearCookies({ name });
  }
  const value = BASE64_PREFIX + stringToBase64URL(JSON.stringify(session));
  const chunks = createChunks(SESSION_KEY, value);
  await context.addCookies(
    chunks.map(({ name, value }) => ({
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
