import { loadEnvFile } from 'node:process';
import path from 'node:path';
import pg from 'pg';

loadEnvFile(path.resolve(import.meta.dirname, '..', '.env'));

function formatWarning(msg: string): string {
  return `\x1b[33m[WARNING]: ${msg}\x1b[0m`;
}

if (!process.env.DATABASE_URL) {
  throw new Error(formatWarning('Missing DATABASE_URL env variable'));
}

const client = new pg.Client({
  connectionString: process.env.DATABASE_URL,
});

try {
  await client.connect();
  await client.end();
} catch {
  console.warn(
    formatWarning('Local docker postgres instance either not initialized or not started')
  );
}
