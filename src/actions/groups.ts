// Group Actions (GRP-01). Each checks who's signed in, and Postgres checks every rule again
// (ADR-004).
import { ActionError, defineAction } from 'astro:actions';
import { actionErrorFor } from '../lib/server/errors';
import { newGroup } from '../lib/validation/group';

export const groups = {
  /** Starting a group, as its owner (GRP-01). Returns its slug, for its address. */
  create: defineAction({
    accept: 'form',
    input: newGroup,
    handler: async (group, { locals }) => {
      if (!locals.user) throw new ActionError({ code: 'UNAUTHORIZED' });

      const { data: slug, error } = await locals.supabase.rpc('create_group', group);
      if (error) throw new ActionError(actionErrorFor(error));
      return { slug };
    },
  }),
};
