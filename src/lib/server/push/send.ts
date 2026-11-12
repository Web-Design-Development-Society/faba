// Sends the pushes that are due (NOTIF-20). The Worker's Cron Trigger runs this every minute
// (src/worker.ts). It claims a batch from the queue, sends each push, and reports how it went,
// until the queue is empty or it has run for 20 seconds.
//
// It runs outside any request, so it reads the Worker's environment directly, not astro:env. It's
// the one job that uses the secret key (design document section 9.6, R-SEC-1), and only to call
// claim_push_deliveries() and finish_push_delivery(), which nothing else can.
import { createClient } from '@supabase/supabase-js';
import type { Database } from '../../db.types';
import { PUSH_DEFAULT_TYPES, pushMessage } from '../../notifications';
import { isPushService, sendPush, type Vapid } from './webpush';

/** The Worker's variables and secrets the sender reads. */
export type PushEnv = {
  SITE_URL: string;
  SUPABASE_URL: string;
  SUPABASE_SECRET_KEY?: string;
  VAPID_PUBLIC_KEY?: string;
  VAPID_PRIVATE_KEY?: string;
};

export type Outcome = 'sent' | 'gone' | 'retry' | 'failed';

/**
 * What a push service's answer means (RFC 8030): delivered, the device unsubscribed, try again
 * later, or a push the service will never take.
 */
export function outcomeOf(status: number): Outcome {
  if (status >= 200 && status < 300) return 'sent';
  if (status === 404 || status === 410) return 'gone';
  if (status === 429 || status >= 500) return 'retry';
  return 'failed';
}

const BATCH = 50;
const BUDGET_MS = 20_000;
/** A push the device can't take within a day is dropped by the push service. */
const TTL_SECONDS = 24 * 60 * 60;

/**
 * Sends what's due, and returns how many pushes went each way. Without the secret key or the VAPID
 * keys it sends nothing, so an environment without push set up just leaves the queue alone.
 */
export async function sendDuePushes(
  env: PushEnv,
  { fetch: send = fetch, now = () => new Date() }: { fetch?: typeof fetch; now?: () => Date } = {}
): Promise<Record<Outcome, number>> {
  const totals: Record<Outcome, number> = { sent: 0, gone: 0, retry: 0, failed: 0 };
  if (!env.SUPABASE_SECRET_KEY || !env.VAPID_PUBLIC_KEY || !env.VAPID_PRIVATE_KEY) return totals;

  const vapid: Vapid = {
    publicKey: env.VAPID_PUBLIC_KEY,
    privateKey: env.VAPID_PRIVATE_KEY,
    subject: env.SITE_URL,
  };
  const local = new URL(env.SITE_URL).hostname === 'localhost';
  const admin = createClient<Database>(env.SUPABASE_URL, env.SUPABASE_SECRET_KEY, {
    auth: { persistSession: false, autoRefreshToken: false },
  });

  const started = Date.now();
  while (Date.now() - started < BUDGET_MS) {
    const { data: due, error } = await admin.rpc('claim_push_deliveries', { max_count: BATCH });
    if (error) throw new Error(`Claiming pushes failed: ${error.message}`);

    await Promise.all(
      due.map(async (delivery) => {
        let outcome: Outcome;
        let problem: string | undefined;
        if (!isPushService(delivery.endpoint, local)) {
          outcome = 'failed';
          problem = 'Not a push service';
        } else {
          try {
            const response = await sendPush(delivery, pushMessage(delivery, now()), vapid, {
              ttl: TTL_SECONDS,
              urgency: PUSH_DEFAULT_TYPES.includes(delivery.type) ? 'high' : 'normal',
              // A newer push of the same notification replaces one still waiting.
              topic: delivery.notification_id.replaceAll('-', ''),
              fetch: send,
            });
            outcome = outcomeOf(response.status);
            if (outcome === 'sent') await response.body?.cancel();
            else problem = `${response.status} ${(await response.text()).slice(0, 200)}`;
          } catch (thrown) {
            outcome = 'retry';
            problem = thrown instanceof Error ? thrown.message : String(thrown);
          }
        }
        totals[outcome]++;
        const finished = await admin.rpc('finish_push_delivery', {
          delivery_id: delivery.delivery_id,
          outcome,
          error: problem,
        });
        // The claim comes round again in 5 minutes, so a lost report only delays a push.
        if (finished.error) console.error(`Reporting a push failed: ${finished.error.message}`);
      })
    );
    if (due.length < BATCH) break;
  }
  return totals;
}
