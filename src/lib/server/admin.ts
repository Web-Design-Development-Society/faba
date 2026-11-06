// The one Supabase client with the secret key (design document section 9.6). The secret key
// bypasses Row Level Security, so only the account-deletion Action may import this module, which
// eslint.config.js enforces. Phase 5's job handlers will be the only others (R-SEC-1).
import { createClient } from '@supabase/supabase-js';
import { SUPABASE_SECRET_KEY, SUPABASE_URL } from 'astro:env/server';

/** Deletes an auth user, which the database's foreign keys follow through (PROF-05). */
export async function deleteAuthUser(id: string) {
  const admin = createClient(SUPABASE_URL, SUPABASE_SECRET_KEY, {
    auth: { persistSession: false, autoRefreshToken: false },
  });
  return admin.auth.admin.deleteUser(id);
}
