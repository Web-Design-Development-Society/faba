# Running Supabase locally

FABA's database, sign-in and email run on your machine in Docker, through the Supabase CLI. `npm install` adds the CLI, so you run it with `npx` and don't install it yourself. [CONTRIBUTING.md](../../CONTRIBUTING.md#set-up) has the short version of these steps. This runbook adds installing Docker, signing in with Google, and what to do when something goes wrong.

Run every command from the `faba` folder.

## 1. Install and start Docker

Any Docker engine works:

- **Docker Desktop** ([download](https://www.docker.com/products/docker-desktop/)) for macOS, Windows and Linux. Open it, and wait until it says it's running.
- **colima** on macOS, instead of Docker Desktop:

  ```zsh
  brew install colima docker
  colima start
  ```

Check that Docker is running. This should print the engine's details, not "Cannot connect to the Docker daemon":

```zsh
docker info
```

## 2. Start Supabase

1. The first time only, copy the Supabase settings. Their placeholder Google values are enough to start:

   ```zsh
   cp supabase/.env.example supabase/.env
   ```

2. Start Supabase. The first run takes 10 to 15 minutes, while Docker downloads the images. It applies the migrations in `supabase/migrations/` and loads the test data in `supabase/seed/`:

   ```zsh
   npx supabase start
   ```

3. Check it. This should show the project `faba`, with its API at `http://127.0.0.1:54331`:

   ```zsh
   npx supabase status
   ```

| Service                             | Address                                                   |
| ----------------------------------- | --------------------------------------------------------- |
| Supabase API                        | <http://127.0.0.1:54331>                                  |
| Supabase Studio (browse the data)   | <http://127.0.0.1:54333>                                  |
| Mailpit (email Supabase would send) | <http://127.0.0.1:54334>                                  |
| Postgres                            | `postgresql://postgres:postgres@127.0.0.1:54332/postgres` |

FABA uses ports 54330 to 54339, so it can run next to another project's Supabase on the default ports, 54320 to 54329.

## 3. Point FABA at it

1. Write `.dev.vars`, which holds the local secret key. Add `-- --force` to rewrite one you already have:

   ```zsh
   npm run setup:dev-vars
   ```

2. Start FABA, and open <http://localhost:4321>:

   ```zsh
   npm run dev
   ```

FABA uses local Supabase unless something tells it otherwise. Make sure nothing does:

- `.dev.vars` holds only `SUPABASE_SECRET_KEY` and `SENTRY_DSN`. Don't add `SUPABASE_URL` or `SITE_URL` to it.
- `CLOUDFLARE_ENV` isn't set, in your shell or in a `.env` file in the `faba` folder. `echo $CLOUDFLARE_ENV` should print nothing. `CLOUDFLARE_ENV=staging` is for CI's staging builds, and it makes FABA use the staging Supabase project instead.

## 4. Sign in with Google

FABA offers only Google sign-in, locally too. The placeholder values from step 2 don't work for it, so you need a Google OAuth client for development. Ask the team for the shared one first. Otherwise, make your own:

1. In the [Google Cloud console](https://console.cloud.google.com/apis/credentials), open **APIs & Services → Credentials**, then **Create credentials → OAuth client ID**.
2. Choose **Web application**. Under **Authorized redirect URIs**, add `http://127.0.0.1:54331/auth/v1/callback`.
3. While the project's consent screen is in **Testing** mode, Google only lets its test users sign in. Add your byui.edu account as one.

Put the client's ID and secret in `supabase/.env`:

```zsh
SUPABASE_AUTH_EXTERNAL_GOOGLE_CLIENT_ID=<the client ID>
SUPABASE_AUTH_EXTERNAL_GOOGLE_SECRET=<the client secret>
```

Supabase reads them only when it starts, so restart it:

```zsh
npx supabase stop
npx supabase start
```

Then sign in at <http://localhost:4321> with your byui.edu account. Other accounts are refused, locally too ([ADR-005](../adr/005-eligibility-gate.md)). Never commit `supabase/.env`, and share a client secret only privately.

## Everyday use

| Command                                    | What it does                                                                                                                         |
| ------------------------------------------ | ------------------------------------------------------------------------------------------------------------------------------------ |
| `npx supabase start` / `npx supabase stop` | Start or stop Supabase. Stopping keeps your data                                                                                     |
| `npx supabase status`                      | Show the addresses and keys                                                                                                          |
| `npx supabase migration up --local`        | Apply new migrations, such as after pulling `main`, and keep your data                                                               |
| `npx supabase db reset`                    | Rebuild the database from the migrations and the test data. **It deletes your local data**, including the account you signed in with |
| `npx supabase stop --no-backup`            | Stop, and delete all of the local data. `npx supabase start` then begins from scratch                                                |

- Every copy of FABA on your machine, including git worktrees, shares one local Supabase: the project `faba`. A reset in one resets it for all of them.
- The sample activities' dates count from the last reset, so they move into the past over time. `npx supabase db reset` brings them forward.

## When something goes wrong

- **"Cannot connect to the Docker daemon":** start Docker Desktop, or run `colima start`.
- **"port is already allocated":** another project's Supabase is using a port in the 5433x range. `docker ps` shows its containers, named `supabase_<service>_<project>`. Run `npx supabase stop` in that project's folder, or `npx supabase stop --project-id <project>` from anywhere.
- **Signing in lands on a live site** instead of <http://localhost:4321>: FABA is using the staging Supabase project, not local Supabase. Staging returns people only to its own addresses, and sends everything else to its Site URL. Remove `SUPABASE_URL` from `.dev.vars`, unset `CLOUDFLARE_ENV`, and restart `npm run dev`.
- **Google says `redirect_uri_mismatch`:** the OAuth client doesn't list `http://127.0.0.1:54331/auth/v1/callback`. Add it exactly, with `127.0.0.1` rather than `localhost`.
- **Google says the OAuth client wasn't found, or `invalid_client`:** `supabase/.env` still has the placeholders, or Supabase hasn't restarted since you changed it.
- **Google says you don't have access to the app:** add your account as a test user on the consent screen.
- **"The following environment variables defined in `env.schema` are invalid":** run `npm run setup:dev-vars -- --force`, which rewrites `.dev.vars`.
- **Containers keep restarting, or `npx supabase start` times out:** give Docker more memory in its settings. With colima, run `colima stop`, then `colima start --memory 8`. Then run `npx supabase stop` and `npx supabase start`.
