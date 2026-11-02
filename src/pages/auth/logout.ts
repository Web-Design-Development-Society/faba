// Signing out of this browser (design document section 9.7, AUTH-03). It's a POST, so a link on
// another site can't sign anyone out. signOut() ends the session in Supabase, so its refresh token
// stops working, and clears the cookies even when Supabase can't be reached.
import type { APIRoute } from 'astro';

export const POST = (async ({ locals, redirect }) => {
  await locals.supabase.auth.signOut({ scope: 'local' });
  return redirect('/', 303);
}) satisfies APIRoute;
