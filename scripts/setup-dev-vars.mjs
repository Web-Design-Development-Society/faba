// Writes .dev.vars from .dev.vars.example, filling in the local Supabase secret key.
// Run after `npx supabase start`: npm run setup:dev-vars (add -- --force to overwrite).
import { execSync } from 'node:child_process';
import { existsSync, readFileSync, writeFileSync } from 'node:fs';
import { join } from 'node:path';

const root = join(import.meta.dirname, '..');
const target = join(root, '.dev.vars');

if (existsSync(target) && !process.argv.includes('--force')) {
  console.error('.dev.vars already exists. Run with -- --force to overwrite it.');
  process.exit(1);
}

let status;
try {
  status = execSync('npx supabase status -o env', { cwd: root, encoding: 'utf8' });
} catch {
  console.error('Could not read the local Supabase status. Is it running? Try: npx supabase start');
  process.exit(1);
}

const secretKey = status.match(/^SECRET_KEY="?([^"\n]+)"?$/m)?.[1];
if (!secretKey) {
  console.error('`npx supabase status -o env` printed no SECRET_KEY.');
  process.exit(1);
}

const example = readFileSync(join(root, '.dev.vars.example'), 'utf8');
writeFileSync(
  target,
  example.replace(/^SUPABASE_SECRET_KEY=.*$/m, `SUPABASE_SECRET_KEY=${secretKey}`)
);
console.log('Wrote .dev.vars with the local Supabase secret key.');
