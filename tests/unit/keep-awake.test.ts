// Keeping a free database awake (OPS-05): once a day, the Cron Trigger calls keep_awake() through
// the Data API with the publishable key, and says how it went without ever throwing.
import { afterEach, describe, expect, it, vi } from 'vitest';
import { isKeepAwakeTime, keepAwake } from '../../src/lib/server/keep-awake';

// The Worker's entry loads Astro's handler, which only the Worker can run.
vi.mock('@astrojs/cloudflare/handler', () => ({ handle: () => new Response() }));

const env = {
  SITE_URL: 'https://faba.example',
  SUPABASE_URL: 'https://project.supabase.co',
  SUPABASE_PUBLISHABLE_KEY: 'sb_publishable_example',
};

afterEach(() => {
  vi.restoreAllMocks();
  vi.unstubAllGlobals();
});

describe('when to ping', () => {
  it('is once a day, at 12:00 UTC', () => {
    expect(isKeepAwakeTime(Date.UTC(2026, 10, 24, 12, 0))).toBe(true);
    expect(isKeepAwakeTime(Date.UTC(2026, 10, 25, 12, 0, 30))).toBe(true);
    expect(isKeepAwakeTime(Date.UTC(2026, 10, 24, 12, 1))).toBe(false);
    expect(isKeepAwakeTime(Date.UTC(2026, 10, 24, 11, 59))).toBe(false);
    expect(isKeepAwakeTime(Date.UTC(2026, 10, 24, 0, 0))).toBe(false);
  });
});

describe('the ping', () => {
  it('calls keep_awake() with the publishable key', async () => {
    const log = vi.spyOn(console, 'log').mockImplementation(() => {});
    const send = vi.fn(async () => Response.json(true));

    expect(await keepAwake(env, { fetch: send })).toBe(true);

    const [url, init] = send.mock.calls[0] as unknown as [URL, RequestInit];
    expect(String(url)).toBe('https://project.supabase.co/rest/v1/rpc/keep_awake');
    expect(init.method).toBe('POST');
    expect(new Headers(init.headers).get('apikey')).toBe('sb_publishable_example');
    expect(log).toHaveBeenCalledWith('{"keep_awake":"ok"}');
  });

  it('logs a failed answer, such as a paused project', async () => {
    const error = vi.spyOn(console, 'error').mockImplementation(() => {});
    const send = vi.fn(async () => new Response('Paused', { status: 540 }));

    expect(await keepAwake(env, { fetch: send })).toBe(false);
    expect(error).toHaveBeenCalledWith('{"keep_awake":"failed","status":540}');
  });

  it('logs a network error without throwing', async () => {
    const error = vi.spyOn(console, 'error').mockImplementation(() => {});
    const send = vi.fn(async () => {
      throw new Error('Network connection lost.');
    });

    expect(await keepAwake(env, { fetch: send })).toBe(false);
    expect(error).toHaveBeenCalledWith(
      '{"keep_awake":"failed","error":"Network connection lost."}'
    );
  });
});

describe('the Cron Trigger', () => {
  /** Runs the Worker's scheduled handler at `time`, and waits for what it started. */
  async function runAt(time: number) {
    const { default: worker } = await import('../../src/worker');
    const started: Promise<unknown>[] = [];
    worker.scheduled({ scheduledTime: time }, env, { waitUntil: (p) => started.push(p) });
    await Promise.all(started);
    return started.length;
  }

  it('pings at 12:00 UTC, beside the pushes, even with push not set up', async () => {
    vi.spyOn(console, 'log').mockImplementation(() => {});
    const send = vi.fn(async () => Response.json(true));
    vi.stubGlobal('fetch', send);

    expect(await runAt(Date.UTC(2026, 10, 24, 12, 0))).toBe(2);
    expect(send).toHaveBeenCalledTimes(1);
    expect(String((send.mock.calls[0] as unknown[])[0])).toContain('/rpc/keep_awake');
  });

  it('only sends pushes the rest of the day', async () => {
    const send = vi.fn(async () => Response.json(true));
    vi.stubGlobal('fetch', send);

    expect(await runAt(Date.UTC(2026, 10, 24, 12, 1))).toBe(1);
    expect(send).not.toHaveBeenCalled();
  });
});
