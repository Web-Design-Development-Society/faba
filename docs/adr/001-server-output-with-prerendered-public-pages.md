# ADR-001: Server output, with public pages prerendered

- **Status:** Accepted
- **Date:** 2026-10-28
- **Decided by:** FABA design document, section 13.2
- **Related:** design document section 9.2

## Context

Nearly every FABA page is personalized and behind sign-in, and activity data changes constantly. A few public pages (about, privacy, guidelines, help) never change. Astro form Actions, which work without JavaScript, need on-demand pages.

## Decision

Use Astro `output: 'server'`, so pages render on demand by default. Only the static public pages set `export const prerender = true`. The landing page (`/`) stays on demand so it can send signed-in members straight to Discover.

## Consequences

- Members get personalized HTML on the first response, with no client-side data fetching and very little JavaScript.
- Every new page is on demand unless it opts in to prerendering.
- Prerendered pages are served before the app runs, so they can't redirect or read the session.
