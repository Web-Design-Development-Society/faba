# Releasing to production

How a change on `main` reaches production, and how to undo it (FND-08, design document sections 11.8 and 11.11). Production deploys with the same steps as staging, in `.github/workflows/deploy.yml`, so every merge to `main` rehearses them.

## Before the first release

Production is the `faba` Worker at `tofaba.org`, set up in `env.production` in `wrangler.jsonc` (FND-09). Its database is the Supabase project `ncfuqxwvpxkqfjjcbpuo`, on the free plan, which has no backups ([ADR-019](../adr/019-free-production-database.md)). Until the GitHub secrets are in, a release stops at **Check the environment is set up**, before anything changes.

Before the first release:

1. **Supabase and Google.** Match the production settings in [supabase-settings.md](supabase-settings.md), all but the hook, which waits for the first deploy.
2. **The picture bucket.** `npx wrangler r2 bucket create faba-media-production`. The deploy fails without it.
3. **GitHub.** The `production` environment (Settings → Environments) needs one of the repository's admins to approve each deploy, and allows deploys only from `main` and from tags matching `v*`. Add its secrets: `CLOUDFLARE_API_TOKEN`, `CLOUDFLARE_ACCOUNT_ID`, `SUPABASE_ACCESS_TOKEN`, `SUPABASE_PROJECT_REF` and `SUPABASE_DB_PASSWORD`. Make the Cloudflare token from the **Edit Cloudflare Workers** template, with the `tofaba.org` zone, since the deploy attaches the custom domain.

Then release as below. Right after the first deploy, before anyone signs in:

4. **Turn on the byui.edu hook** ([supabase-settings.md](supabase-settings.md#production-faba-at-tofabaorg)). The migrations made the function it calls. Check it with a personal Gmail account.
5. **Worker secrets.** `npx wrangler secret put SUPABASE_SECRET_KEY --env production`, with the project's secret key from **Project Settings → API Keys**. Account deletion needs it. The `faba` Worker exists only once it's deployed, so this waits for the first release.
6. **Push, when you want it.** Run `npm run push:keys`. Put the public key in `env.production.vars.VAPID_PUBLIC_KEY` in `wrangler.jsonc` through a pull request, and the private key in with `npx wrangler secret put VAPID_PRIVATE_KEY --env production`. Push stays off until both are in.
7. **Appoint the first admins** ([roles.md](roles.md)), at least 2.

The accounts belong to the FABA organization, with at least 2 owners and MFA, never one volunteer's personal account.

## Releasing

1. **Pick a time** when a maintainer is around for the next 2 hours. Avoid Fridays and exam weeks.
2. **Check `main`.** CI and **Deploy staging** passed for the commit you're releasing, and the change works on staging.
3. **Back up first for a risky migration**, such as one that rewrites or drops data. On the free plan, link the production project with `npx supabase link --project-ref <its ref>`, then save a copy of its data on your own computer with `npx supabase db dump --remote --data-only -f faba-<date>.sql`. It holds members' data, so keep it private, never in GitHub, and delete it once the release is fine. On Pro, take an on-demand backup in the Supabase dashboard instead ([restore-backup.md](restore-backup.md)).
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
