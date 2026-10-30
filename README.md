# Astro Starter Kit: Minimal

## Dev Setup

See [CONTRIBUTING.md](./CONTRIBUTING.md)

## Project Structure

Inside of your Astro project, you'll see the following folders and files:

```text
/
├── docs/                  design document, ADRs and runbooks
├── public/
├── scripts/               developer helpers and smoke tests
├── src/
│   ├── layouts/
│   ├── lib/server/        Supabase client and sign-in helpers
│   ├── middleware.ts      session check on every request
│   └── pages/             including auth/ for sign-in and sign-out
├── supabase/
│   ├── config.toml        local Supabase settings
│   ├── migrations/        database schema, applied in order
│   └── seed/              local test data, and sample data for staging
├── astro.config.mjs       Astro settings and env.schema
├── wrangler.jsonc         Cloudflare Worker settings
├── tests/
│   ├── e2e/               Playwright with axe
│   └── unit/              Vitest
├── playwright.config.ts   end-to-end test settings
└── package.json
```

Astro looks for `.astro` or `.md` files in the `src/pages/` directory. Each page is exposed as a route based on its file name.

There's nothing special about `src/components/`, but that's where we like to put any Astro/React/Svelte components.

Any static assets, like images, can be placed in the `public/` directory.

FABA Stack and Roles
Frontend - Sam
Backend - Alex
Google OAuth - Josh
Deployment - UNKNOWN
Postgres - Nefi
Hosting - Alvey

Float - Zelda

FABA - Faculty Associations Board Activities: A hub for Faculty Members at ___ to
view, save and add activities and events for other members of the faculty. Goal is to keep
it light so that it will run easily on mobile devices. We hope to add the capacity to notify users of upcoming events, and maybe even add events to google calander.
