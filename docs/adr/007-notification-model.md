# ADR-007: Notification model

- **Status:** Accepted
- **Date:** 2026-10-28
- **Decided by:** FABA design document, section 13.2
- **Related:** design document sections 8.8 and 9.12

## Context

Notifications start in-app in Phase 2. Email arrives in Phase 5a and SMS possibly in Phase 5b. The model shouldn't need rebuilding when channels are added.

## Decision

- Postgres writes one `notifications` row per recipient, in the same transaction as the change that caused it.
- Each row carries a typed payload snapshot, so it still reads correctly after the activity changes.
- There is one creation path for all notification types.
- Email and SMS arrive as `notification_deliveries` rows, one per channel, on top of the same model.

## Consequences

- In-app notifications are consistent with the data that caused them.
- Adding a channel adds delivery rows and a sender, not a new notification system.
