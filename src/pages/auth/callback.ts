// Google sends people back here through Supabase after they choose an account (design document
// section 9.7).
import type { APIRoute } from 'astro';
import { ALLOWED_EMAIL_DOMAIN } from 'astro:env/server';
import {
  callbackFailure,
  isEligibleGoogleUser,
  NEXT_COOKIE,
  safeNextPath,
  signInErrorPath,
} from '../../lib/server/auth';

export const GET = (async ({ url, cookies, locals, redirect }) => {
  const next = safeNextPath(cookies.get(NEXT_COOKIE)?.value);
  cookies.delete(NEXT_COOKIE, { path: '/auth' });

  const code = url.searchParams.get('code');
  if (!code) {
    const failure = callbackFailure(url.searchParams, ALLOWED_EMAIL_DOMAIN);
    return redirect(failure === 'not-eligible' ? '/not-eligible' : signInErrorPath(failure, next));
  }

  const { data, error } = await locals.supabase.auth.exchangeCodeForSession(code);
  if (error) return redirect(signInErrorPath('failed', next));

  // The callback check (ADR-005). Signing out leaves no session behind.
  if (!isEligibleGoogleUser(data.user, ALLOWED_EMAIL_DOMAIN)) {
    await locals.supabase.auth.signOut({ scope: 'local' });
    return redirect('/not-eligible');
  }

  // The middleware sends new members through Welcome first (PROF-01).
  return redirect(next);
}) satisfies APIRoute;
