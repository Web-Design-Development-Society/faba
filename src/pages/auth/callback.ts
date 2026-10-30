// Google sends people back here through Supabase after they choose an account (design document
// section 9.7).
import type { APIRoute } from 'astro';
import { ALLOWED_EMAIL_DOMAIN } from 'astro:env/server';
import { isAllowedEmail, NEXT_COOKIE, safeNextPath } from '../../lib/server/auth';

export const GET = (async ({ url, cookies, locals, redirect }) => {
  const next = safeNextPath(cookies.get(NEXT_COOKIE)?.value);
  cookies.delete(NEXT_COOKIE, { path: '/auth' });

  const code = url.searchParams.get('code');
  if (!code) {
    // When the byui.edu hook rejects a new account, Supabase passes on the hook's message, which
    // names the domain. Anything else, such as cancelling at Google, goes back to sign-in.
    const reason = url.searchParams.get('error_description') ?? '';
    return redirect(reason.includes(ALLOWED_EMAIL_DOMAIN) ? '/not-eligible' : '/auth/login?error');
  }

  const { data, error } = await locals.supabase.auth.exchangeCodeForSession(code);
  if (error) return redirect('/auth/login?error');

  // The callback check (ADR-005): the domain again, and that Google verified the email.
  if (!isAllowedEmail(data.user.email, ALLOWED_EMAIL_DOMAIN) || !data.user.email_confirmed_at) {
    await locals.supabase.auth.signOut({ scope: 'local' });
    return redirect('/not-eligible');
  }

  return redirect(next);
}) satisfies APIRoute;
