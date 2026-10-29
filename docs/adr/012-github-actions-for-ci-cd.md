# ADR-012: GitHub Actions for CI/CD

- **Status:** Accepted
- **Date:** 2026-10-28
- **Decided by:** FABA design document, section 13.2
- **Related:** design document sections 11.5 to 11.9; FND-07, FND-08

## Context

Database migrations must run before the Worker that depends on them is deployed. Cloudflare's Git integration deploys the Worker but doesn't control that order.

## Decision

GitHub Actions runs all checks and deployments. Each deploy applies migrations first, then deploys the Worker. Migrations follow expand/contract, so rolling back the Worker never breaks the database.

## Consequences

- One workflow file owns the deploy order for staging and production.
- Every schema change ships in steps: add, migrate data, then remove in a later release.
