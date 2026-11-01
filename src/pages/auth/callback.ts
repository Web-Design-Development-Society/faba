// Google sends people back here through Supabase after they choose an account (design document
// section 9.7).
import type { APIRoute } from 'astro';
import { ALLOWED_EMAIL_DOMAIN } from 'astro:env/server';
import {
  afterSignInPath,
  callbackFailure,
  isAllowedEmail,
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

  // The callback check (ADR-005): the domain again, and that Google verified the email.
  if (!isAllowedEmail(data.user.email, ALLOWED_EMAIL_DOMAIN) || !data.user.email_confirmed_at) {
    await locals.supabase.auth.signOut({ scope: 'local' });
    return redirect('/not-eligible');
  }

  // Members who haven't accepted the community guidelines are new (PROF-01).
  const { data: profile } = await locals.supabase
    .from('profiles')
    .select('guidelines_accepted_at')
    .eq('id', data.user.id)
    .maybeSingle();
  const isNewMember = profile !== null && profile.guidelines_accepted_at === null;
  return redirect(afterSignInPath(isNewMember, next));
}) satisfies APIRoute;
