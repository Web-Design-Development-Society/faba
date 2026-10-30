// What src/middleware.ts puts on Astro.locals for every request.
declare namespace App {
  interface Locals {
    supabase: import('./lib/server/supabase').Supabase;
    /** The signed-in member, or null for visitors. */
    user: { id: string; email: string } | null;
  }
}
