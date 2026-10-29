# ADR-002: A single Cloudflare Worker hosts the Astro app

- **Status:** Accepted
- **Date:** 2026-10-28
- **Decided by:** FABA design document, section 13.2
- **Related:** design document sections 9.1 and 9.3; ADR-014

## Context

FABA is a small app run by volunteers. Each extra service is something else to deploy, secure and pay for.

## Decision

One Cloudflare Worker per environment runs the whole Astro app, built with `@astrojs/cloudflare`: pages, Astro Actions, a few API routes, and (from Phase 5) `scheduled` and `queue` handlers through a custom entrypoint. There is no separate API service. If a second Worker is ever justified, it is called through a Service Binding, never over public HTTP.

## Consequences

- Astro and the "backend" talk through in-process function calls, not network calls.
- Business rules live in Postgres (ADR-004), not in a separate service.
- [ADR-014](014-cloudflare-and-supabase-stack.md) replaces the `@astrojs/node` adapter the repository started with.
