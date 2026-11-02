import { defineMiddleware } from 'astro:middleware';
// Importing astro:env/server checks every variable in env.schema, so a missing or invalid one
// fails every request with an error that names it.
import { ALLOWED_EMAIL_DOMAIN } from 'astro:env/server';
import { isAllowedEmail } from './lib/server/auth';
import { createSupabase } from './lib/server/supabase';

// Pages anyone can open without signing in (design document section 9.7). New members read the
// guidelines here before they accept them on Welcome.
const PUBLIC_PATHS = new Set([
  '/',
  '/auth/login',
  '/auth/callback',
  '/auth/logout',
  '/not-eligible',
  '/guidelines',
  '/api/health',
]);

export const onRequest = defineMiddleware(async (context, next) => {
  // Prerendered pages are built once for everyone, so there's no session to read.
  if (context.isPrerendered) return next();

  const supabase = createSupabase(context);
  context.locals.supabase = supabase;

  // getClaims() checks the session's signature, and refreshes the session when it has expired.
  // Never trust getSession() to say who's signed in.
  const { data } = await supabase.auth.getClaims();
  const claims = data?.claims;
  context.locals.user = claims ? { id: claims.sub, email: claims.email ?? '' } : null;

  // A session whose email isn't byui.edu, for example after the account's email changed.
  if (context.locals.user && !isAllowedEmail(context.locals.user.email, ALLOWED_EMAIL_DOMAIN)) {
    await supabase.auth.signOut({ scope: 'local' });
    context.locals.user = null;
    if (context.url.pathname !== '/not-eligible') {
      return noStore(context.redirect('/not-eligible'));
    }
  }

  const back = encodeURIComponent(context.url.pathname + context.url.search);
  if (!context.locals.user && !PUBLIC_PATHS.has(context.url.pathname)) {
    return noStore(context.redirect(`/auth/login?next=${back}`));
  }

  // The signed-in member's status and display details, for the pages that need sign-in.
  context.locals.member = null;
  if (context.locals.user && !PUBLIC_PATHS.has(context.url.pathname)) {
    const { data: member } = await supabase.rpc('get_session_context').maybeSingle();
    context.locals.member = member;
    // Until they accept the current guidelines, members see only Welcome (PROF-01).
    if (member && !member.guidelines_ok && context.url.pathname !== '/welcome') {
      return noStore(context.redirect(`/welcome?next=${back}`));
    }
  }

  return noStore(await next());
});

// Pages depend on who's signed in, and refreshed sessions set cookies, so browsers and
// Cloudflare must never cache them.
function noStore(response: Response) {
  response.headers.set('Cache-Control', 'private, no-store');
  return response;
}
