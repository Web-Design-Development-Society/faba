# Releasing to production

How a change on `main` reaches production, and how to undo it (FND-08, design document sections 11.8 and 11.11). Production deploys with the same steps as staging, in `.github/workflows/deploy.yml`, so every merge to `main` rehearses them.

## Before the first release

Production doesn't exist yet (FND-09). Until it does, a release stops at **Check the environment is set up**, before anything changes. To set it up:

1. **Supabase.** Create the production project on a paid plan in a US West region, check its backups, and match the settings in [supabase-settings.md](supabase-settings.md). Add the production Google OAuth client to its Auth settings.
2. **`wrangler.jsonc`.** Add `env.production`, copying `env.staging`: its own `SITE_URL`, `SUPABASE_URL`, `SUPABASE_PUBLISHABLE_KEY`, R2 bucket and custom domain, `LOG_LEVEL` set to `info`, the Cron Trigger, and a `VAPID_PUBLIC_KEY` from `npm run push:keys`. Leave out `workers_dev` and `preview_urls`.
3. **Worker secrets.** `npx wrangler secret put <NAME> --env production` for `SUPABASE_SECRET_KEY`, `VAPID_PRIVATE_KEY` (the pair's private key) and `SENTRY_DSN`.
4. **GitHub.** The `production` environment (Settings → Environments) needs one of the repository's admins to approve each deploy, and allows deploys only from `main` and from tags matching `v*`. Add its secrets: `CLOUDFLARE_API_TOKEN`, `CLOUDFLARE_ACCOUNT_ID`, `SUPABASE_ACCESS_TOKEN`, `SUPABASE_PROJECT_REF` and `SUPABASE_DB_PASSWORD`.

The accounts belong to the FABA organization, with at least 2 owners and MFA, never one volunteer's personal account.

## Releasing

1. **Pick a time** when a maintainer is around for the next 2 hours. Avoid Fridays and exam weeks.
2. **Check `main`.** CI and **Deploy staging** passed for the commit you're releasing, and the change works on staging.
3. **Back up first for a risky migration**, such as one that rewrites or drops data. Take an on-demand backup in the Supabase dashboard ([restore-backup.md](restore-backup.md)).
4. **Publish a release.** On GitHub, open Releases → **Draft a new release**. Type a new tag, `vX.Y.Z`, on `main`. Bump the middle number for new features, and the last for fixes only. Choose **Generate release notes**, then **Publish release**. Don't tick **Set as a pre-release**: a pre-release doesn't deploy.
5. **Approve.** **Deploy production** starts. **Check the release** confirms the tag is on `main`, then the deploy waits for approval. One of the repository's admins opens the run in the Actions tab, chooses **Review deployments**, and approves `production`.
6. **Watch it run:** build, migrations, the Worker, then smoke tests. If the build fails, nothing has changed. If migrations fail, the Worker isn't deployed.
7. **Verify** by signing in with a real `@byui.edu` account, then opening Discover, an activity and Alerts.
8. **Announce** it in the board's channel, with a link to the release notes.

The workflow deploys to all traffic at once. Gradual rollouts (design document section 11.8) aren't automated.

## Rolling back

- **Fastest:** `npx wrangler rollback --env production` puts the previous Worker version back in about a minute. The database stays as it is.
- **To a chosen release:** in the Actions tab, run **Deploy production** with an earlier release's tag and **Roll back** ticked. It needs approval like any release, and leaves out migrations.

Either way, the database only moves forward. Migrations are written expand-then-contract (design document section 11.9), so the earlier code still works with the newer schema. To undo a bad migration, write a new one that fixes it, and release that. Restore a backup only after losing data ([restore-backup.md](restore-backup.md)).
