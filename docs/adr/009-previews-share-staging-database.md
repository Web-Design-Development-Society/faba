# ADR-009: Previews share the staging database

- **Status:** Accepted, revisit at Phase 3
- **Date:** 2026-10-28
- **Decided by:** FABA design document, section 13.2
- **Related:** design document section 11.6; ADR-013

## Context

Each pull request gets a preview deployment. A database per pull request (Supabase Branching) is a paid feature.

## Decision

Previews run against the staging Supabase project and its synthetic data. Pull requests with migrations are checked by the CI database job, and reviewers test the migration locally.

## Consequences

- Pull requests without migrations get fully working previews.
- A preview for a pull request with migrations runs against the current staging schema, and is labeled that way.
- If migration-heavy pull requests become common, revisit Supabase Branching in a new ADR.
