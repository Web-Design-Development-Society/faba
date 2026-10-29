# ADR-004: Writes to rule-bearing tables go through definer functions

- **Status:** Accepted
- **Date:** 2026-10-28
- **Decided by:** FABA design document, section 13.2
- **Related:** design document sections 9.8 and 10.5

## Context

Rules such as RSVP capacity, quotas, notification fan-out and the moderation audit log must hold even when someone calls the Data API directly with their own token. Row-level policies alone can't enforce multi-step rules.

## Decision

Writes to rule-bearing tables happen only through `SECURITY DEFINER` RPC functions, one per user action. Members may update only their own columns directly, such as their profile fields.

## Consequences

- One round trip per user action, and each rule is tested once, in SQL.
- Definer functions must check the caller themselves, so each one needs pgTAP tests and CODEOWNERS review.
- Rule of thumb: if an invariant must hold against direct API calls, it belongs in Postgres. If it's about presentation or flow, it belongs in Astro.
