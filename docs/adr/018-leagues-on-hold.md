# ADR-018: Leagues are on hold; FABA starts with basic groups

- **Status:** Accepted
- **Date:** 2026-11-14
- **Decided by:** Zack Alvey
- **Related:** LEAG-01 to LEAG-09, GRP-01, NOTIF-10; design document sections 6.7 and 7.3

## Context

Leagues (Phase 4: seasons, teams, schedules, scores, standings, subs, availability, ladders and playoffs) are built. Before launch, the team decided to keep FABA simple and start with basic interest groups. Leagues may come back once members are using groups.

## Decision

Leagues are switched off, not removed:

- `LEAGUES` in `src/lib/features.ts` is `false`.
- Nothing in the app leads to a league:
  - Discover → Groups has no **Start a league**.
  - A league's page has no **Seasons**, and its card has no **League** badge.
  - Me → Notifications doesn't offer **A sub is needed**.
- `/leagues/new` and a group's `/seasons` page answer "not found", and every league Action refuses.
- The league pages, components, Actions, validation, database tables and functions, and their tests stay.

Setting `LEAGUES` to `true` brings leagues back as they were.

## Consequences

- **Groups:** a league made before this shows as an ordinary group.
- **Tests:** the league E2E tests (`leagues`, `ladder`, `playoffs` and `game-availability`) skip while leagues are off, and `leagues-on-hold.spec.ts` checks that nothing leads to them. The database tests and unit tests for leagues still run.
- **Upkeep:** while they're off, league pages aren't exercised end to end, so turning leagues back on should start with a full E2E run with `LEAGUES` set to `true`.
- **Revisit:** once groups are in use, or when members ask for leagues.
