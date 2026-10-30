// The Supabase client for one request, acting as whoever its cookies say is signed in (design
// document section 9.6). It uses the publishable key, so Row Level Security applies to every
// query. Create a new one for each request.
import { createServerClient, parseCookieHeader } from '@supabase/ssr';
import type { APIContext } from 'astro';
import { SUPABASE_PUBLISHABLE_KEY, SUPABASE_URL } from 'astro:env/server';
import type { Database } from '../db.types';
import { authCookieOptions } from './auth';

export function createSupabase({ request, cookies, url }: APIContext) {
  return createServerClient<Database>(SUPABASE_URL, SUPABASE_PUBLISHABLE_KEY, {
    cookieOptions: authCookieOptions(url),
    cookies: {
      getAll: () => parseCookieHeader(request.headers.get('cookie') ?? ''),
      // The library also passes no-cache headers. The middleware already sets Cache-Control on
      // every response, so they aren't needed here.
      setAll: (cookiesToSet) => {
        for (const { name, value, options } of cookiesToSet) cookies.set(name, value, options);
      },
    },
  });
}

export type Supabase = ReturnType<typeof createSupabase>;
