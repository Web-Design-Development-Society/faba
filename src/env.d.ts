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

// The picture bucket (MEDIA-01), bound as MEDIA in wrangler.jsonc. Only the methods the Worker uses.
interface MediaBucket {
  put(
    key: string,
    value: ArrayBuffer,
    options?: { httpMetadata?: { contentType?: string } }
  ): Promise<unknown>;
  get(key: string): Promise<{
    body: ReadableStream;
    size: number;
    httpEtag: string;
    httpMetadata?: { contentType?: string };
  } | null>;
  delete(keys: string | string[]): Promise<void>;
}

// The Cloudflare runtime's module, which Astro's adapter provides at build time. Its bindings are
// read by name, so the type stays loose here; each file says what it expects.
declare module 'cloudflare:workers' {
  export const env: Record<string, unknown>;
}
