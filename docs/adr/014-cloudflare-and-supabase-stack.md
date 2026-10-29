# ADR-014: Replace the Node adapter and Compose Postgres with Cloudflare and Supabase

- **Status:** Accepted
- **Date:** 2026-10-29
- **Decided by:** Zack Alvey (FND-02)
- **Related:** design document sections 9 and 11.2; FND-06, FND-09; open questions 7 and 8; ADR-002, ADR-003, ADR-013

## Context

The design document is built on Cloudflare Workers and Supabase. The repository started differently:

- The `@astrojs/node` adapter in standalone mode, added so `npm run build` works.
- Postgres 18 in Docker Compose (`compose.yml`), loaded by `scripts/init-db.ts`.
- Empty Google OAuth endpoints in `src/pages/api/auth/`.

FND-06 asked for the two to be reconciled. The target is to launch Phase 1 as soon as possible, during Fall 2026, and to use free tiers until launch (open questions 7 and 8).

## Decision

Use the stack in the design document:

- **App:** Astro on Cloudflare Workers, built with `@astrojs/cloudflare` ([ADR-002](002-single-cloudflare-worker.md)).
- **Auth and database:** Supabase. Supabase Auth handles Google sign-in and sessions, and Postgres RLS handles permissions ([ADR-003](003-server-only-supabase-access.md)).

Environments follow section 11.2 of the design document:

| Environment | App                       | Database and auth                                                   | Google OAuth client |
| ----------- | ------------------------- | ------------------------------------------------------------------- | ------------------- |
| Local       | `astro dev`               | Supabase CLI (`supabase start`, Docker)                             | Dev                 |
| Preview     | Per-PR version of staging | Staging project ([ADR-009](009-previews-share-staging-database.md)) | Staging             |
| Staging     | `faba-staging` Worker     | Staging project, synthetic data only                                | Staging             |
| Production  | `faba` Worker             | Production project                                                  | Production          |

Local, preview and staging use the Cloudflare and Supabase free plans until launch.

**Still open:** who pays for production hosting, and which plan it starts on. Owner: Zack Alvey, to settle with the board by 2026-11-13. The pilot runs in production ([ADR-013](013-synthetic-staging-pilot-in-production.md)), so this must be settled before the pilot starts.

## Consequences

- FND-06 replaces `@astrojs/node` with `@astrojs/cloudflare`, replaces `compose.yml` and `scripts/init-db.*` with Supabase migrations and `supabase/seed.sql`, and updates `CONTRIBUTING.md`. Contributors still need Docker, because the Supabase CLI runs on it.
- The Google OAuth stubs in `src/pages/api/auth/` are replaced by the Supabase Auth flow in section 9.7, with its `/auth/callback` route.
- The existing `/api/health` endpoint can stay, or move to `/healthz` as section 9.3 lists.
- Free projects on Supabase pause after a period without activity, so a quiet staging project may need waking up before demos or previews.
- FND-09 expects production on a paid plan with verified backups. If production starts on a free plan, update FND-09 and record that choice in a new ADR.
