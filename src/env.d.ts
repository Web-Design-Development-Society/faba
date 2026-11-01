// What src/middleware.ts puts on Astro.locals for every request.
declare namespace App {
  interface Locals {
    supabase: import('./lib/server/supabase').Supabase;
    /** The signed-in member, or null for visitors. */
    user: { id: string; email: string } | null;
    /** The signed-in member's profile details on pages that need sign-in, or null. */
    member:
      | import('./lib/db.types').Database['public']['Functions']['get_session_context']['Returns'][number]
      | null;
  }
}
