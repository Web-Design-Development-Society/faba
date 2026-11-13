# Handover: start here

For a new volunteer maintainer. It says what runs, where the rest is written down, and what is still missing before the handover (OPS-02) is complete.

## Read these runbooks first

- [local-supabase.md](local-supabase.md): running the app and the database on your own machine.
- [release.md](release.md): releasing to production, and rolling back.
- [restore-backup.md](restore-backup.md): restoring the database from a backup.
- [supabase-settings.md](supabase-settings.md): the settings to check in the Supabase dashboard.
- [roles.md](roles.md): who can do what, including the owner and the admin roles.
- [audit-log.md](audit-log.md): what the audit log records, and how to read it.
- [takedown.md](takedown.md): removing content or an account.
- [transfer-account.md](transfer-account.md): handing a group or activity to someone else.

The decisions behind the stack are in [docs/adr](../adr/README.md).

## What runs on a schedule

These run in the database with pg_cron (ADR-006). Each one is in a migration, so the schedule is in the code.

| Job                     | When (UTC)       | What it does                                                                                                                                                       |
| ----------------------- | ---------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------ |
| `send-reminders`        | every 15 minutes | Writes in-app reminders for activities coming up.                                                                                                                  |
| `top-up-series`         | 09:00 daily      | Adds upcoming dates to recurring activities.                                                                                                                       |
| `purge-old-data`        | 10:30 daily      | Deletes notifications older than 90 days.                                                                                                                          |
| `enforce-retention`     | 10:45 daily      | Deletes private details, reports and audit rows past their retention (see `docs/faba-design-document.md`, section 9.14). Each run is recorded in `retention_runs`. |
| `compute-daily-metrics` | 11:15 daily      | Computes yesterday's board metrics. Groups under 10 are never stored.                                                                                              |

To see the jobs and their last runs, use the `cron.job` and `cron.job_run_details` tables in the Supabase SQL editor.

The Worker has one more: a Cloudflare Cron Trigger, every minute, that sends the Web Push notifications that are due (NOTIF-20, ADR-006). It's in `wrangler.jsonc`, and the code is `src/lib/server/push/send.ts`.

- **Its queue** is the `notification_deliveries` table. A push still `pending` long after it was queued, or `failed`, shows what isn't getting through, and `last_error` says why.
- **Its runs** show in the Worker's logs and under the Worker's Cron Events in the Cloudflare dashboard. A run that sent anything logs how many pushes went each way.
- **It needs keys.** Each environment has its own VAPID key pair: the public key in `wrangler.jsonc`, and the private key as the `VAPID_PRIVATE_KEY` secret. Without the secret, push stays off and the queue isn't sent. Make a pair with `npm run push:keys`. Changing an environment's keys stops pushes to every device until its member turns push on again.

## Everyday commands

```bash
npm run dev            # the app, against local Supabase
npm run db:test        # the database tests (pgTAP)
npm test               # the unit tests
npm run typecheck      # Astro and TypeScript
npm run db:types       # regenerate the database types after a migration
```

## Known gaps before handover is complete

- **Walkthrough recording.** Not yet recorded. The architecture is in `docs/faba-design-document.md`, and the ADRs explain the decisions.
- **On-call rota.** Not yet set up. There needs to be at least two volunteers who can restore the service.
- **Mean time to restore under 1 hour.** Not yet tested. Run the restore in `restore-backup.md` on staging, time it, and write the result here.
