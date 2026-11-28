# Supabase settings

Migrations set up the database, but some Supabase settings live only in each project's dashboard. This runbook lists them, so staging and production can be checked against it (Iteration 1 task AU-2). Locally, `supabase/config.toml` holds the same settings.

Change this file in the same pull request as anything that needs a new dashboard setting, and apply the setting after the pull request merges.

## Staging (`faba-staging`)

Open the project at <https://supabase.com/dashboard>, then:

| Setting                       | Where                                             | Value                                                                                                                                  |
| ----------------------------- | ------------------------------------------------- | -------------------------------------------------------------------------------------------------------------------------------------- |
| Google sign-in                | **Authentication → Sign In / Providers → Google** | Enabled, with the client ID and secret of the "FABA staging" Google OAuth client, which production shares (ADR-020)                    |
| Email sign-in                 | **Authentication → Sign In / Providers → Email**  | Disabled. Staging and production are Google-only (design document section 11.2)                                                        |
| Other providers and anonymous | **Authentication → Sign In / Providers**          | All disabled                                                                                                                           |
| Site URL                      | **Authentication → URL Configuration**            | `https://faba-staging.zack-alvey.workers.dev`                                                                                          |
| Redirect URLs                 | **Authentication → URL Configuration**            | `https://faba-staging.zack-alvey.workers.dev/**` and, for pull request previews, `https://*-faba-staging.zack-alvey.workers.dev/**`    |
| byui.edu hook                 | **Authentication → Hooks → Before User Created**  | Enabled, type **Postgres**, schema `private`, function `before_user_created`. It rejects every account that isn't `byui.edu` (ADR-005) |
| Refresh tokens                | **Authentication → Sessions**                     | Rotation on, with a 10-second reuse interval (the defaults)                                                                            |
| Inactivity timeout            | **Authentication → Sessions**                     | 30 days (AUTH-03). Supabase offers it only on paid plans. Without it, sessions last until sign-out                                     |
| Exposed schemas               | **Project Settings → Data API**                   | `public` and `graphql_public` only. Never expose `private`                                                                             |

To check the hook, try to sign in to staging with a personal Gmail account. FABA should refuse it, and **Authentication → Users** shouldn't list the account.

The consent screen must stay published, since production uses the same client. In **Testing** mode, Google lets only the test users listed in Google Cloud sign in, so every other member would be locked out of production.

## Production (`faba`, at `tofaba.org`)

The project `ncfuqxwvpxkqfjjcbpuo`, on the free plan ([ADR-019](../adr/019-free-production-database.md)). Open it at <https://supabase.com/dashboard>, then:

| Setting                       | Where                                             | Value                                                                                                                                  |
| ----------------------------- | ------------------------------------------------- | -------------------------------------------------------------------------------------------------------------------------------------- |
| Google sign-in                | **Authentication → Sign In / Providers → Google** | Enabled, with the client ID and secret of the "FABA staging" Google OAuth client, the same as staging (ADR-020)                        |
| Email sign-in                 | **Authentication → Sign In / Providers → Email**  | Disabled                                                                                                                               |
| Other providers and anonymous | **Authentication → Sign In / Providers**          | All disabled                                                                                                                           |
| Site URL                      | **Authentication → URL Configuration**            | `https://tofaba.org`                                                                                                                   |
| Redirect URLs                 | **Authentication → URL Configuration**            | `https://tofaba.org/**` only                                                                                                           |
| byui.edu hook                 | **Authentication → Hooks → Before User Created**  | Enabled, type **Postgres**, schema `private`, function `before_user_created`. It rejects every account that isn't `byui.edu` (ADR-005) |
| Refresh tokens                | **Authentication → Sessions**                     | Rotation on, with a 10-second reuse interval (the defaults)                                                                            |
| Inactivity timeout            | **Authentication → Sessions**                     | Not on the free plan. Set 30 days (AUTH-03) when production moves to Pro                                                               |
| Exposed schemas               | **Project Settings → Data API**                   | `public` and `graphql_public` only. Never expose `private`                                                                             |

**The hook waits for the first release.** The migrations make `private.before_user_created`, so it can't be chosen before then. Turn it on right after the first deploy, before anyone signs in ([release.md](release.md#before-the-first-release)), then check it with a personal Gmail account as for staging.

### The Google client

Production and staging share the "FABA staging" client, because BYU-Idaho's Google Workspace blocked a new client for production with `Error 400: admin_policy_enforced` ([ADR-020](../adr/020-shared-google-client.md)). The name says staging, but it's the right client for both. Don't delete it or swap in a new one.

- **Authorized redirect URIs:** both `https://qptrhaxvrozdozhuhagb.supabase.co/auth/v1/callback` (staging) and `https://ncfuqxwvpxkqfjjcbpuo.supabase.co/auth/v1/callback` (production). Removing either one breaks that environment's sign-in.
- **Consent screen:** `tofaba.org` is an authorized domain, with `https://tofaba.org` as the home page and `https://tofaba.org/privacy` as the privacy policy. It's **published**, not in **Testing**, so any `byui.edu` account can sign in.
- **Rotating the secret:** add a new secret to the client, put it in both projects, then disable the old one.
