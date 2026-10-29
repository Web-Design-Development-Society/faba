# ADR-013: Staging holds only synthetic data; the pilot runs in production

- **Status:** Accepted
- **Date:** 2026-10-28
- **Decided by:** FABA design document, section 13.2
- **Related:** design document section 11.2; FND-09, FND-11

## Context

Staging is used for demos, preview deployments and rehearsing migrations, and preview URLs are semi-public. Real member data shouldn't be exposed there.

## Decision

Staging and previews hold only synthetic data and team accounts. The Phase 1 pilot group (FND-11) uses production as a quiet soft launch before the public announcement.

## Consequences

- Production must exist, with real Google sign-in, before the pilot starts. That's why who pays for production hosting must be settled first ([ADR-014](014-cloudflare-and-supabase-stack.md)).
- Pilot data carries over into the public launch, so there's no migration from a separate pilot system.
