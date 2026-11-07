// RSVP Actions. Each checks who's signed in, and rsvp() checks every rule again (ADR-004).
import { ActionError, defineAction } from 'astro:actions';
import { z } from 'astro/zod';
import { actionErrorFor } from '../lib/server/errors';

export const rsvps = {
  /**
   * I'm in (RSVP-01), its Undo, Can't make it (RSVP-02), Maybe (RSVP-05) and guests (RSVP-06).
   * Without a number of guests, a member going keeps theirs. Returns the RSVP and the going count.
   */
  set: defineAction({
    accept: 'form',
    input: z.object({
      activity_id: z.uuid(),
      status: z.enum(['going', 'maybe', 'not_going']),
      guests: z.number({ error: 'Enter a number of guests.' }).int().min(0).max(5).optional(),
    }),
    handler: async ({ activity_id, status, guests }, { locals }) => {
      if (!locals.user) throw new ActionError({ code: 'UNAUTHORIZED' });

      const { data: going_count, error } = await locals.supabase.rpc('rsvp', {
        activity_id,
        status,
        guests,
      });
      if (error) throw new ActionError(actionErrorFor(error));
      return { activity_id, status, going_count };
    },
  }),
};
