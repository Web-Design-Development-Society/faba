# ADR-008: Denormalized RSVP counts

- **Status:** Accepted
- **Date:** 2026-10-28
- **Decided by:** FABA design document, section 13.2
- **Related:** design document sections 10.3 and 10.5

## Context

Activity cards and capacity checks need the going count on every page. Counting RSVP rows each time is wasteful, but a stored count can drift.

## Decision

`activities.going_count` and `guest_total` are stored on the activity and changed **only** by the `rsvp()` function. A nightly `pg_cron` job reconciles them against the RSVP rows.

## Consequences

- Cards and capacity checks read one column.
- Nothing else may write these columns. A drift found by reconciliation is a bug to investigate.
