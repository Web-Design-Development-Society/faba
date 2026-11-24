// Keeping a free database awake (OPS-05, ADR-019). Supabase pauses a free project after 7 days
// without activity, so once a day the Worker's every-minute Cron Trigger (src/worker.ts) also calls
// keep_awake() through the Data API. It uses the publishable key, which needs no secret, and runs
// whether or not push is set up. It reports how it went in the Worker's logs and never throws, so
// it can't stop the pushes.

/** The Worker's variables the ping reads. */
export type AwakeEnv = {
  SUPABASE_URL: string;
  SUPABASE_PUBLISHABLE_KEY: string;
};

/**
 * Whether the Cron Trigger's run at `scheduledTime` pings: once a day, at 12:00 UTC. Daily, not
 * weekly, so a missed run or two still leaves the project well inside its 7 days.
 */
export function isKeepAwakeTime(scheduledTime: number): boolean {
  const at = new Date(scheduledTime);
  return at.getUTCHours() === 12 && at.getUTCMinutes() === 0;
}

/** Calls keep_awake(), logs how it went, and says whether it answered. */
export async function keepAwake(
  env: AwakeEnv,
  { fetch: send = fetch }: { fetch?: typeof fetch } = {}
): Promise<boolean> {
  try {
    const response = await send(new URL('/rest/v1/rpc/keep_awake', env.SUPABASE_URL), {
      method: 'POST',
      headers: { apikey: env.SUPABASE_PUBLISHABLE_KEY, 'Content-Type': 'application/json' },
      body: '{}',
    });
    if (response.ok) {
      console.log(JSON.stringify({ keep_awake: 'ok' }));
      return true;
    }
    console.error(JSON.stringify({ keep_awake: 'failed', status: response.status }));
  } catch (error) {
    console.error(
      JSON.stringify({
        keep_awake: 'failed',
        error: error instanceof Error ? error.message : String(error),
      })
    );
  }
  return false;
}
