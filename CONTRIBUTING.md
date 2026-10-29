# Dev Setup

## Installation Requirements

- [node.js](https://nodejs.org/en)
- [docker](https://docs.docker.com/reference/cli/docker/)
- [colima](https://github.com/abiosoft/colima), [Docker Desktop](https://www.docker.com/products/docker-desktop/) or some other docker engine

See also VS Code [extension recommendations](.vscode/extensions.json)

## Using the development database

Use `docker context ls` to see which docker engine is being used

1. colima start
2. docker compose up

Use `docker compose down` to end these services.

### Database Setup

Use the [init.db.ts](./scripts/init-db.ts) to insert data into the database.

## Environment Variables

Copy `.env.sample` to `.env`.

## Running the App

After starting docker and install dependencies, you can run the local dev server.

```zsh
npm install
npm run dev
```

## Documentation Links

- [Astro](https://docs.astro.build)
