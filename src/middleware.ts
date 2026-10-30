import { defineMiddleware } from 'astro:middleware';
// Importing astro:env/server checks every variable in env.schema, so a missing or invalid one
// fails every request with an error that names it.
import { ALLOWED_EMAIL_DOMAIN } from 'astro:env/server';
import { isAllowedEmail } from './lib/server/auth';
import { createSupabase } from './lib/server/supabase';

// Pages anyone can open without signing in (design document section 9.7).
const PUBLIC_PATHS = new Set([
  '/',
  '/auth/login',
  '/auth/callback',
  '/auth/logout',
  '/not-eligible',
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

  if (!context.locals.user && !PUBLIC_PATHS.has(context.url.pathname)) {
    const back = context.url.pathname + context.url.search;
    return noStore(context.redirect(`/auth/login?next=${encodeURIComponent(back)}`));
  }

  return noStore(await next());
});

// Pages depend on who's signed in, and refreshed sessions set cookies, so browsers and
// Cloudflare must never cache them.
function noStore(response: Response) {
  response.headers.set('Cache-Control', 'private, no-store');
  return response;
}
