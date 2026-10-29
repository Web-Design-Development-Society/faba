# ADR-003: Server-only Supabase access with the user's JWT

- **Status:** Accepted
- **Date:** 2026-10-28
- **Decided by:** FABA design document, section 13.2
- **Related:** design document sections 9.4, 9.6 and 9.8

## Context

Supabase can be called from the browser or from the server. Calling it from the browser exposes the session to scripts and spreads data access across two places.

## Decision

- Only the Worker calls Supabase. There is no Supabase client in the browser, and auth cookies are `HttpOnly`.
- The Worker calls the Supabase Data API with the signed-in user's JWT and the publishable key, so Row Level Security (RLS) applies to every user request.
- The secret key, which bypasses RLS, is used only in `src/lib/server/admin.ts`, and only by account deletion and (later) Phase 5 jobs. A lint rule enforces this.
- No direct Postgres connections or Hyperdrive, because they would bypass RLS unless application code set the role on every transaction.

## Consequences

- RLS is the single authorization layer, and it is tested with pgTAP.
- Each page aims for 2 or fewer round trips to Supabase.
- Revisit before adding any browser-side Supabase feature, such as Realtime (see PERF-01).
