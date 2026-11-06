# Restoring from a backup

Restore the database only when data is lost or corrupted (design document section 11.11). It isn't the fix for anything else:

- A bad deploy: roll the Worker back with `wrangler rollback`.
- A migration bug that lost no data: ship a forward-fix migration.

## What there is to restore

- **Production** goes on Supabase's Pro plan, which backs the database up every day and keeps the last 7 days (FND-09, DP-8). Point-in-time recovery is an add-on to consider once real usage begins.
- **Staging** is on the free plan, which has no backups. Its data is synthetic, so run **Seed staging** from the Actions tab instead.

Supabase's [backups guide](https://supabase.com/docs/guides/platform/backups) has the current dashboard steps.

## What a restore loses

A restore replaces the whole database with the backup's copy, and the database holds the sign-in accounts and the audit log too. Everything after the backup is gone:

- activities, RSVPs and reports
- moderation: hidden activities, suspensions and role changes
- **account deletions**. Members who deleted their account since the backup come back, and they must be deleted again.
- new accounts. Those members sign in again and start over.

## Restore

1. **Agree on it with a second admin or technical owner,** and pick the backup: the latest one before the problem began.
2. **Tell members** in the board's channel that FABA is down for maintenance. FABA has no read-only mode yet, so anything they post now is lost.
3. **Save what the restore will lose.** In the **SQL Editor**, run this with the backup's time and download the result as CSV:

   ```sql
   SELECT created_at, actor_id, action, target_type, target_id, reason, metadata
   FROM private.audit_log
   WHERE created_at > '<the backup''s time>'
   ORDER BY id;
   ```

4. **Restore it:** **Database → Backups** in the dashboard, choose the backup, then **Restore**. The project is unavailable until it finishes, from minutes to longer for a big database.
5. **Re-apply newer migrations.** The backup has the schema from its own time. Re-run the latest deploy workflow for the environment in the Actions tab, which pushes any migrations the backup doesn't have.
6. **Redo what the restore lost,** from the CSV:
   - **Account deletions first.** For each `delete_account` row, delete that account again, as [Moving a member to a new account](transfer-account.md#delete-the-old-account) shows.
   - Then hides, suspensions and role changes, with the moderation tools and [Appointing moderators and admins](roles.md).
7. **Check it:** run `node scripts/smoke-test.mjs <the site's URL>`, then sign in with a byui.edu account and open an activity.
8. **Tell members** FABA is back, and what was lost.

## Practice

Practice a restore once a semester, so it isn't the first time when it matters. Restore the latest production backup into a **new** project, which Supabase's guide recommends for any restore that should keep the current data. Check that it has recent activities and accounts, then delete the new project. Never practice on production itself.
