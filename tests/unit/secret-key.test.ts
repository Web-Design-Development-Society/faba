import { describe, expect, it } from 'vitest';
import config from '../../astro.config.mjs';
import { isSecretKey } from '../../src/lib/server/secret-key';

describe('isSecretKey', () => {
  it('accepts a Supabase secret key', () => {
    expect(isSecretKey('sb_secret_example')).toBe(true);
  });

  it.each([
    ['missing', undefined],
    ['empty', ''],
    ['the legacy service_role key', 'eyJhbGciOiJIUzI1NiJ9.e30.example'],
    ['the publishable key', 'sb_publishable_ACJWlzQHlZjBrEguHvfOxg_3BJgxAaH'],
    ['pasted with a space first', ' sb_secret_example'],
    ['pasted in quotes', '"sb_secret_example"'],
  ])('refuses one that is %s', (_, value) => {
    expect(isSecretKey(value)).toBe(false);
  });
});

// astro:env checks secrets on every request, so one with a format check that a deployment's value
// fails breaks every page. That took down production once.
describe("astro.config.mjs's secrets", () => {
  const secrets = Object.entries(config.env?.schema ?? {}).filter(
    ([, field]) => field.access === 'secret'
  );

  it('lists the secrets FABA reads', () => {
    expect(secrets.map(([name]) => name).sort()).toEqual([
      'SENTRY_DSN',
      'SUPABASE_SECRET_KEY',
      'VAPID_PRIVATE_KEY',
    ]);
  });

  it.each(secrets)('%s is an optional string with no format check', (_, field) => {
    expect(field).toEqual({ context: 'server', access: 'secret', type: 'string', optional: true });
  });
});
