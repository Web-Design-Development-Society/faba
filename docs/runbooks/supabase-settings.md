# Supabase settings

Migrations set up the database, but some Supabase settings live only in each project's dashboard. This runbook lists them, so staging and production can be checked against it (Iteration 1 task AU-2). Locally, `supabase/config.toml` holds the same settings.

Change this file in the same pull request as anything that needs a new dashboard setting, and apply the setting after the pull request merges.

## Staging (`faba-staging`)

Open the project at <https://supabase.com/dashboard>, then:

| Setting                       | Where                                             | Value                                                                                                                                  |
| ----------------------------- | ------------------------------------------------- | -------------------------------------------------------------------------------------------------------------------------------------- |
| Google sign-in                | **Authentication → Sign In / Providers → Google** | Enabled, with the client ID and secret of the "FABA staging" Google OAuth client                                                       |
| Email sign-in                 | **Authentication → Sign In / Providers → Email**  | Disabled. Staging and production are Google-only (design document section 11.2)                                                        |
| Other providers and anonymous | **Authentication → Sign In / Providers**          | All disabled                                                                                                                           |
| Site URL                      | **Authentication → URL Configuration**            | `https://faba-staging.zack-alvey.workers.dev`                                                                                          |
| Redirect URLs                 | **Authentication → URL Configuration**            | `https://faba-staging.zack-alvey.workers.dev/**` and, for pull request previews, `https://*-faba-staging.zack-alvey.workers.dev/**`    |
| byui.edu hook                 | **Authentication → Hooks → Before User Created**  | Enabled, type **Postgres**, schema `private`, function `before_user_created`. It rejects every account that isn't `byui.edu` (ADR-005) |
| Refresh tokens                | **Authentication → Sessions**                     | Rotation on, with a 10-second reuse interval (the defaults)                                                                            |
| Exposed schemas               | **Project Settings → Data API**                   | `public` and `graphql_public` only. Never expose `private`                                                                             |

To check the hook, try to sign in to staging with a personal Gmail account. FABA should refuse it, and **Authentication → Users** shouldn't list the account.

While the Google consent screen is in **Testing** mode, Google only lets the test users listed in Google Cloud sign in. Add the accounts you test with, including any personal account you use to check the hook.

## Production

Set up with FND-09. It uses the same settings, with the production URLs and the production Google client.
