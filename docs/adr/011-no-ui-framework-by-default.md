# ADR-011: No UI framework by default

- **Status:** Accepted
- **Date:** 2026-10-28
- **Decided by:** FABA design document, section 13.2
- **Related:** design document section 9.2

## Context

Most FABA members are on phones. Server-rendered pages need very little JavaScript, and the budget is 30 KB gzipped or less per page.

## Decision

Pages ship no framework JavaScript. Progressive enhancement uses small vanilla TypeScript modules, for example optimistic RSVP, unread-badge polling, local form drafts, and the Web Share API. Add a Preact island only when a component becomes genuinely stateful, such as a Phase 4 standings editor.

## Consequences

- Pages stay fast and work without JavaScript.
- Adding a framework later is a deliberate choice, recorded in its own ADR.
