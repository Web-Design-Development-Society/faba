# ADR-006: pg_cron for data jobs

- **Status:** Accepted
- **Date:** 2026-10-28
- **Decided by:** FABA design document, section 13.2
- **Related:** design document sections 9.3 and 9.12

## Context

FABA needs scheduled work: reminders, purging private details after activities, generating recurring activities, and later, sending email and SMS.

## Decision

- Jobs that only touch data run inside Postgres with `pg_cron`.
- Cloudflare Cron Triggers and Queues are added only in Phase 5, for delivery to external channels such as email and SMS.

## Consequences

- Data jobs run next to the data, under the same RLS-aware functions, with no extra service.
- The Phase 5 custom Worker entrypoint needs a spike to confirm the `scheduled` handler works with the Astro adapter.
