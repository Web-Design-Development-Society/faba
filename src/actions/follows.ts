// Following a category or group (NOTIF-09). Each checks who's signed in, and Postgres checks the
// category or group exists and can be followed.
import { ActionError, defineAction } from 'astro:actions';
import { z } from 'astro/zod';
import { actionErrorFor } from '../lib/server/errors';

export const follows = {
  /** Follows or unfollows a category or group. Returns whether the member now follows it. */
  set: defineAction({
    accept: 'form',
    input: z.object({
      kind: z.enum(['category', 'group']),
      target: z.string().min(1).max(64),
      follow: z.boolean(),
    }),
    handler: async ({ kind, target, follow }, { locals }) => {
      if (!locals.user) throw new ActionError({ code: 'UNAUTHORIZED' });

      const { data, error } = await locals.supabase.rpc('set_follow', { kind, target, follow });
      if (error) throw new ActionError(actionErrorFor(error));
      return { following: data };
    },
  }),
};
