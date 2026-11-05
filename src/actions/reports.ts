// Report Actions. Each checks who's signed in, and report_content() checks every rule again
// (ADR-004).
import { ActionError, defineAction } from 'astro:actions';
import { actionErrorFor } from '../lib/server/errors';
import { newReport } from '../lib/validation/report';

export const reports = {
  /** Reporting an activity or a member (MOD-01). Returns what was reported. */
  create: defineAction({
    accept: 'form',
    input: newReport,
    handler: async ({ target_type, target_id, reason, note }, { locals }) => {
      if (!locals.user) throw new ActionError({ code: 'UNAUTHORIZED' });

      const { error } = await locals.supabase.rpc('report_content', {
        target_type,
        target_id,
        reason,
        note,
      });
      if (error) throw new ActionError(actionErrorFor(error));
      return { target_type, target_id };
    },
  }),
};
