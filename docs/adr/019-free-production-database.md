# ADR-019: Production starts on Supabase's free plan, kept awake by a daily ping

- **Status:** Accepted
- **Date:** 2026-11-24
- **Decided by:** Zack Alvey (FND-09)
- **Related:** FND-09, OPS-05, AUTH-03; [ADR-013](013-synthetic-staging-pilot-in-production.md), [ADR-014](014-cloudflare-and-supabase-stack.md); design document sections 11.2 and 11.11

## Context

ADR-014 left open who pays for production and which plan it starts on, and FND-09 expected Supabase's Pro plan, with verified backups. FABA is ready to go live with real data at `tofaba.org`, but there's no hosting budget yet.

Supabase's free plan differs from Pro in ways that matter to FABA:

- **It pauses a project after 7 days without activity.** While it's paused, every page that reads data fails, until an owner restores it from the dashboard.
- **It has no backups to restore from.** Pro backs up every day and keeps the last 7 days.
- **Sign-in sessions can't time out after inactivity.** AUTH-03's 30-day timeout is a paid setting, so a session lasts until the member signs out.
- **Its limits are lower:** a 500 MB database, and 2 free projects for each Supabase organization, which staging and production use up.

## Decision

- Production's Supabase project starts on the free plan, in a US West region.
- Once a day, the Worker's Cron Trigger makes a small query through the Data API (OPS-05), in staging and production. The project never goes 7 days without activity.
- Before a risky migration, such as one that rewrites or drops data, a technical owner saves a copy of the data with `npx supabase db dump --remote --data-only` on their own computer. They keep it private, out of GitHub, and delete it once the release is fine.
- Production moves to Pro ($25 a month) as soon as any of these happens:
  - The board has a budget for it.
  - The database passes 400 MB.
  - The project pauses despite the ping.

## Consequences

- FND-09's paid plan and verified backups wait for the move to Pro.
- **Data can be lost.** A bad migration or a mistake in the dashboard can't be undone from a backup, only from a dump taken by hand. Migrations stay expand-then-contract and reviewed (section 11.9), and the dump before a risky one is the safety net.
- Sessions last until sign-out until the move to Pro, when [supabase-settings.md](../runbooks/supabase-settings.md)'s inactivity timeout gets set.
- **If the ping fails,** the Worker's logs say so, days before the project would pause. If it pauses anyway, an owner restores it from the dashboard, and that's a trigger to move to Pro.
- The ping costs nothing, so it can stay after the move to Pro, and it keeps staging awake for demos and previews too.
