// The Worker's entry (FND-08, NOTIF-20). Astro answers every request, and the Cron Trigger in
// wrangler.jsonc sends the pushes that are due, every minute. Once a day, it also keeps a free
// Supabase project from pausing (OPS-05).
import { handle } from '@astrojs/cloudflare/handler';
import { isKeepAwakeTime, keepAwake, type AwakeEnv } from './lib/server/keep-awake';
import { sendDuePushes, type PushEnv } from './lib/server/push/send';

export default {
  fetch: handle,
  scheduled(
    controller: { scheduledTime: number },
    env: PushEnv & AwakeEnv,
    context: { waitUntil(promise: Promise<unknown>): void }
  ) {
    context.waitUntil(
      sendDuePushes(env).then((totals) => {
        if (Object.values(totals).some(Boolean)) console.log(JSON.stringify({ push: totals }));
      })
    );
    if (isKeepAwakeTime(controller.scheduledTime)) context.waitUntil(keepAwake(env));
  },
};
