// Activity Actions. Each checks who's signed in, and Postgres checks every rule again (ADR-004).
import { ActionError, defineAction } from 'astro:actions';
import { actionErrorFor } from '../lib/server/errors';
import { newActivity } from '../lib/validation/activity';

export const activities = {
  /** Posting an activity (ACT-03). Returns its id. */
  create: defineAction({
    accept: 'form',
    input: newActivity,
    handler: async (activity, { locals }) => {
      if (!locals.user) throw new ActionError({ code: 'UNAUTHORIZED' });

      const { data: id, error } = await locals.supabase.rpc('create_activity', activity);
      if (error) throw new ActionError(actionErrorFor(error));
      return { id };
    },
  }),
};
