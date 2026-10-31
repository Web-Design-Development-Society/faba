# Contributing to FABA

FABA is an Astro app that runs as a Cloudflare Worker, with Supabase for sign-in and the database ([ADR-014](docs/adr/014-cloudflare-and-supabase-stack.md)). Locally, both run on your machine: Astro on Cloudflare's `workerd` runtime, and Supabase in Docker.

## What you need

- [Node.js](https://nodejs.org/en) 22.23.4 or later (`node --version`).
- A Docker engine: [Docker Desktop](https://www.docker.com/products/docker-desktop/), [colima](https://github.com/abiosoft/colima), or another. The Supabase CLI runs the local database and auth in Docker.

You don't need to install the Supabase CLI or Wrangler. `npm install` adds both, and you run them with `npx`.

See also the VS Code [extension recommendations](.vscode/extensions.json).

## Set up

The first run takes about 10 to 15 minutes, mostly while Docker downloads the Supabase images.

1. Clone the repository and install dependencies:

   ```zsh
   git clone https://github.com/Web-Design-Development-Society/faba.git
   cd faba
   npm install
   ```

2. Copy the Supabase settings. The placeholder Google values are enough for everything except Google sign-in:

   ```zsh
   cp supabase/.env.example supabase/.env
   ```

3. Start Supabase. Docker must be running. This applies the migrations in `supabase/migrations/` and loads the test data in `supabase/seed/`:

   ```zsh
   npx supabase start
   ```

4. Write `.dev.vars`, which holds local secrets. This fills in the local Supabase secret key for you:

   ```zsh
   npm run setup:dev-vars
   ```

5. Start Astro and open <http://localhost:4321>:

   ```zsh
   npm run dev
   ```

   <http://localhost:4321/api/health> should return `{"status":"ok", ...}`.

To keep the dev server running in the background, use `npx astro dev --background`. Manage it with `npx astro dev stop`, `npx astro dev status`, and `npx astro dev logs`.

## Local services

| Service                             | Address                                                   |
| ----------------------------------- | --------------------------------------------------------- |
| FABA                                | <http://localhost:4321>                                   |
| Supabase API                        | <http://127.0.0.1:54331>                                  |
| Supabase Studio (browse the data)   | <http://127.0.0.1:54333>                                  |
| Mailpit (email Supabase would send) | <http://127.0.0.1:54334>                                  |
| Postgres                            | `postgresql://postgres:postgres@127.0.0.1:54332/postgres` |

FABA uses ports 54330 to 54339 instead of Supabase's default 54320 to 54329, so it can run next to other local Supabase projects.

## Test data

`supabase/seed/local_accounts.sql` creates five personas, each with the password `faba-local-dev`. FABA itself offers only Google sign-in, so the passwords are for automated tests and the Supabase API. To sign in to FABA locally, set up Google sign-in (see [Environment variables](#environment-variables)) and use your own byui.edu account.

| Email                     | Name             | Role      | Notes                                   |
| ------------------------- | ---------------- | --------- | --------------------------------------- |
| `member.test@byui.edu`    | Maya Member      | member    | Part-time faculty                       |
| `organizer.test@byui.edu` | Oscar Organizer  | member    | Organizes most activities; shares email |
| `moderator.test@byui.edu` | Morgan Moderator | moderator | Hid the commercial post                 |
| `admin.test@byui.edu`     | Ada Admin        | admin     |                                         |
| `suspended.test@byui.edu` | Sam Suspended    | member    | Suspended; posted the hidden activity   |

`supabase/seed/sample_data.sql` fills in their profiles and creates 50 activities over the next 6 weeks in Rexburg time, with none on Sundays. Two are cancelled and one is hidden. Dates count from when the database was last reset, so run `npx supabase db reset` to bring them forward.

Row Level Security is on for every table. Through the Data API, signed-out visitors read nothing. Active `byui.edu` members read categories, activities that aren't hidden, and active profiles. Suspended members read only their own profile. Use Studio or `psql` to see everything.

Only `byui.edu` accounts can be created, locally too: the before-user-created hook rejects every other email (ADR-005).

## Everyday commands

| Command                                 | What it does                                                |
| --------------------------------------- | ----------------------------------------------------------- |
| `npm run dev`                           | Run Astro on `workerd`, with hot reload                     |
| `npm run build`, then `npm run preview` | Build the Worker and run the built version locally          |
| `npx supabase start` / `stop`           | Start or stop local Supabase. Stopping keeps your data      |
| `npx supabase db reset`                 | Rebuild the local database from the migrations and the seed |
| `npx supabase migration new <name>`     | Create a migration file in `supabase/migrations/`           |
| `npx supabase status`                   | Show local URLs and keys                                    |

## Checks

Every pull request runs these checks in GitHub Actions (`.github/workflows/ci.yml`). Run the same commands locally before you push:

| Check      | Command                                         | Notes                                                            |
| ---------- | ----------------------------------------------- | ---------------------------------------------------------------- |
| Format     | `npm run format:check`                          | Fix with `npx prettier --write <files>`                          |
| Typecheck  | `npm run typecheck`                             | Runs `astro check`                                               |
| Unit tests | `npm test`                                      | Vitest, in `tests/unit/`                                         |
| Database   | `npx supabase db reset`, then `npm run db:test` | pgTAP tests in `supabase/tests/`. CI also runs lint and advisors |
| Types      | `npm run db:types`                              | Regenerates `src/lib/db.types.ts`. CI fails if it's out of date  |
| Build      | `npm run build`                                 |                                                                  |
| E2E        | `npm run test:e2e`                              | Playwright with axe. See [End-to-end tests](#end-to-end-tests)   |

Use the pull request template, and keep pull requests to about 400 changed lines. Changes to the database, auth, middleware, environment settings or CI request a review from the technical owners in `.github/CODEOWNERS`.

## End-to-end tests

The end-to-end tests in `tests/e2e/` drive Chromium through FABA with [Playwright](https://playwright.dev), at desktop and Pixel 7 sizes. Each page they visit is also checked with [axe](https://github.com/dequelabs/axe-core-npm/tree/develop/packages/playwright), and a serious or critical accessibility problem fails the test.

1. Install Chromium for Playwright, once:

   ```zsh
   npx playwright install chromium
   ```

2. Start local Supabase and write `.dev.vars`, as in [Set up](#set-up). The tests expect the seed data, so if the activities' dates have passed, run `npx supabase db reset`.

3. Run the tests:

   ```zsh
   npm run test:e2e
   ```

They build FABA and run the built Worker with `astro preview` on port 4329, so a dev server on 4321 can keep running. Add `--ui` (`npm run test:e2e -- --ui`) to watch them step by step. After a failure, `npx playwright show-report` opens the report with a trace of each failed test. In CI, the report is attached to the run as `playwright-report`.

Tests sign in as a persona with the `signInAs` fixture in `tests/e2e/fixtures.ts`, which uses the persona's password instead of Google. Sign-in tests stop at the redirect to Google. Call `expectAccessible(page)` on each new page or state a test visits.

## Deployments

| Environment | Deploys                                               | Address                                                                        |
| ----------- | ----------------------------------------------------- | ------------------------------------------------------------------------------ |
| Preview     | On every push to a pull request                       | `https://pr-<number>-faba-staging.zack-alvey.workers.dev`, commented on the PR |
| Staging     | On every merge to `main`                              | <https://faba-staging.zack-alvey.workers.dev>                                  |
| Production  | Not set up yet. A release tag will deploy it (FND-08) |                                                                                |

- **Staging** (`.github/workflows/deploy-staging.yml`) pushes new migrations to the staging Supabase project first, then deploys the `faba-staging` Worker, then runs `scripts/smoke-test.mjs` against it.
- **Previews** (`.github/workflows/preview.yml`) are versions of the `faba-staging` Worker, so they use the staging database. Migrations in a pull request don't reach its preview, so test them locally. Pull requests from forks and Dependabot get no preview.
- Staging holds only synthetic data. Its free Supabase project pauses after a week without activity. Restore it from the Supabase dashboard.
- **Sample data on staging:** run **Seed staging** from the Actions tab. It adds the five personas as accounts nobody can sign in to, and their 50 activities. Run it again to move the activities' dates forward.
- To set a staging secret, run `npx wrangler secret put <NAME> --name faba-staging`. GitHub's `staging` environment holds the secrets the workflows use.

## Database changes

- Migrations are forward-only SQL files in `supabase/migrations/`. Never edit one that's already on `main`. Add a new one.
- After adding or changing a migration, run `npx supabase db reset` to check that everything applies from zero, then `npm run db:types` and commit the regenerated types.
- Add pgTAP tests in `supabase/tests/database/` for new tables, policies and functions.
- Design document section 10 describes the schema, section 9.8 describes Row Level Security, and section 12.9 describes the database tests.

## Environment variables

- Every variable is declared in `env.schema` in `astro.config.mjs`. If one is missing or invalid, every request fails with an error naming it.
- Non-secret values live in the `vars` of `wrangler.jsonc`, with a separate block for each deployed environment. Secrets live in `.dev.vars` locally, and in `wrangler secret put` for deployed environments. Never commit `.dev.vars` or `supabase/.env`.
- To add a variable, add it to `env.schema`, to `wrangler.jsonc` or `.dev.vars.example`, and to section 11.10 of the design document.
- **Google sign-in locally** needs a Google OAuth client for development. Put its ID and secret in `supabase/.env`, add `http://127.0.0.1:54331/auth/v1/callback` as an authorized redirect URI, then restart Supabase.

## Troubleshooting

- **"port is already allocated" from `npx supabase start`:** another project is using a port in the 5433x range. `docker ps` shows what's running. Run `npx supabase stop` in that project's folder.
- **"The following environment variables defined in `env.schema` are invalid":** check `.dev.vars` (`npm run setup:dev-vars -- --force` rewrites it) and the `vars` in `wrangler.jsonc`.
- **"Cannot connect to the Docker daemon":** start Docker Desktop or colima first.

## Formatting

A pre-commit hook runs Prettier on staged files. To format by hand, run `npx prettier --write <files>`.

## Documentation

- [FABA design document](docs/faba-design-document.md) and [architecture decision records](docs/adr/README.md)
- [Supabase settings](docs/runbooks/supabase-settings.md) for staging and production, which live in the dashboard rather than in migrations
- [Astro](https://docs.astro.build) and its [Cloudflare adapter](https://docs.astro.build/en/guides/integrations-guide/cloudflare/)
- [Supabase local development](https://supabase.com/docs/guides/local-development)
