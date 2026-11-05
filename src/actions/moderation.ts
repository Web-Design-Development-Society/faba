// Moderation Actions. Each checks who's signed in, and Postgres checks that they moderate and every
// rule again (ADR-004).
import { ActionError, defineAction } from 'astro:actions';
import { actionErrorFor } from '../lib/server/errors';
import { dismissal } from '../lib/validation/moderation';

export const moderation = {
  /** Dismissing a report from the queue, with a reason (MOD-02). Returns its id. */
  dismiss: defineAction({
    accept: 'form',
    input: dismissal,
    handler: async ({ report_id, reason }, { locals }) => {
      if (!locals.user) throw new ActionError({ code: 'UNAUTHORIZED' });

      const { error } = await locals.supabase.rpc('dismiss_report', { report_id, reason });
      if (error) throw new ActionError(actionErrorFor(error));
      return { report_id };
    },
  }),
};
