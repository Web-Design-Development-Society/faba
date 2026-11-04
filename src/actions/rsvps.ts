// RSVP Actions. Each checks who's signed in, and rsvp() checks every rule again (ADR-004).
import { ActionError, defineAction } from 'astro:actions';
import { z } from 'astro/zod';
import { actionErrorFor } from '../lib/server/errors';

export const rsvps = {
  /** I'm in (RSVP-01), its Undo, and Can't make it (RSVP-02). Returns the RSVP and the count. */
  set: defineAction({
    accept: 'form',
    input: z.object({
      activity_id: z.uuid(),
      status: z.enum(['going', 'not_going']),
    }),
    handler: async ({ activity_id, status }, { locals }) => {
      if (!locals.user) throw new ActionError({ code: 'UNAUTHORIZED' });

      const { data: going_count, error } = await locals.supabase.rpc('rsvp', {
        activity_id,
        status,
      });
      if (error) throw new ActionError(actionErrorFor(error));
      return { activity_id, status, going_count };
    },
  }),
};
