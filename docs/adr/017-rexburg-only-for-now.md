# ADR-017: Phase 1 serves in-person Rexburg activities only

- **Status:** Accepted
- **Date:** 2026-10-29
- **Decided by:** Zack Alvey (FND-02, open question 5)
- **Related:** PROF-02, PROF-03, ACT-01, ACT-02, ACT-03, SRCH-03, NOTIF-02, FND-11; goal G4

## Context

Many part-time faculty are remote or online-only. The design document's default shipped "Online" activities and a "based in" profile field in Phase 1, and revisited regions after Phase 2. The target is to launch Phase 1 as soon as possible, during Fall 2026.

## Decision

For now, FABA is for in-person activities in the Rexburg area:

- No "Online" activities: every activity has a place, not a link.
- No "based in" field on profiles.
- No regions beyond Rexburg.

Revisit when remote faculty ask for it, or after Phase 2 usage data.

## Consequences

- **Phase 1 stories:**
  - PROF-02 drops the "based in" field and the online-first Home default.
  - PROF-03 drops "based in" from what's hidden.
  - ACT-01 and ACT-02 drop the online variants.
  - ACT-03 drops the Online toggle and the time zone option meant for remote activities. The database still stores the time zone (risk R-TECH-2).
- **Phase 2 stories:** SRCH-03 drops the In person / Online filter, and NOTIF-02 drops "online link" from the changes it reports.
- **FND-11:** pilot recruiting no longer needs remote faculty, and the user acceptance test plan in section 12.11 no longer needs 3 remote or online faculty.
- **Data model:** `activities.location_type` and `online_url` can wait. `FR-ACT-1`, `FR-PROF-3`, `FR-PROF-5` and `FR-SRCH-4` need matching edits.
- Goal G4 (include part-time and remote faculty) is partly deferred. Part-time faculty in Rexburg are still served.
