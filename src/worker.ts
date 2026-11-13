// The Worker's entry (FND-08, NOTIF-20). Astro answers every request, and the Cron Trigger in
// wrangler.jsonc sends the pushes that are due, every minute.
import { handle } from '@astrojs/cloudflare/handler';
import { sendDuePushes, type PushEnv } from './lib/server/push/send';

export default {
  fetch: handle,
  scheduled(
    _controller: unknown,
    env: PushEnv,
    context: { waitUntil(promise: Promise<unknown>): void }
  ) {
    context.waitUntil(
      sendDuePushes(env).then((totals) => {
        if (Object.values(totals).some(Boolean)) console.log(JSON.stringify({ push: totals }));
      })
    );
  },
};
