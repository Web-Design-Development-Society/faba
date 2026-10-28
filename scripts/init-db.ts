import fs from 'node:fs/promises';
import { join } from 'node:path';
import { Client, Pool } from 'pg';

/**
 * node --env-file=.env scripts/init-db.ts
 *
 * This script initializes the database schema by executing the SQL found in init-db.sql
 * DO NOT run this on prod
 * DO NOT wipe the production database
 */

const connectionString = process.env.DATABASE_URL;
if (!connectionString) {
  console.error('❌ DATABASE_URL is not defined in environment variables.');
  process.exit(1);
}

let exitCode = 0;
const dbUrl = new URL(connectionString);
const dbName = dbUrl.pathname.slice(1);

dbUrl.pathname = '/postgres';

const client = new Client({
  connectionString: dbUrl.toString(),
});
let pool: Pool | undefined;

try {
  await client.connect();

  const { rowCount } = await client.query('SELECT 1 FROM pg_database WHERE datname = $1', [dbName]);

  if (!rowCount) {
    console.info(`Creating database "${dbName}"...`);
    await client.query(`CREATE DATABASE "${dbName}"`);
  }

  pool = new Pool({
    connectionString,
  });

  console.info('Reading SQL setup script...');
  const tableSql = await fs.readFile(join(import.meta.dirname, 'init-db.sql'), 'utf8');

  // Execute the full SQL script
  console.info('Connecting to database and executing schema...');

  // Create tables and insert data
  await pool.query(tableSql);

  console.info('✅ Database initialized successfully.');
} catch (error) {
  console.error('❌ Failed to initialize database:', error);
  exitCode = 1;
} finally {
  await client.end();
  await pool?.end();
}

process.exit(exitCode);
