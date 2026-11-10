// Group Actions (GRP-01, GRP-02). Each checks who's signed in, and Postgres checks every rule again
// (ADR-004).
import { ActionError, defineAction } from 'astro:actions';
import { z } from 'astro/zod';
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

  /**
   * Joining a group (GRP-02): at once for an open group, or a request to its organizers. Returns the
   * membership, `active` or `pending`.
   */
  join: defineAction({
    accept: 'form',
    input: z.object({ group_id: z.uuid() }),
    handler: async ({ group_id }, { locals }) => {
      if (!locals.user) throw new ActionError({ code: 'UNAUTHORIZED' });

      const { data: status, error } = await locals.supabase.rpc('join_group', { group_id });
      if (error) throw new ActionError(actionErrorFor(error));
      return { status: status as 'active' | 'pending' };
    },
  }),

  /** Leaving a group, or withdrawing a request to join (GRP-02). Returns what they had. */
  leave: defineAction({
    accept: 'form',
    input: z.object({ group_id: z.uuid(), pending: z.boolean().optional() }),
    handler: async ({ group_id, pending }, { locals }) => {
      if (!locals.user) throw new ActionError({ code: 'UNAUTHORIZED' });

      const { error } = await locals.supabase.rpc('leave_group', { group_id });
      if (error) throw new ActionError(actionErrorFor(error));
      return { pending: !!pending };
    },
  }),
};
