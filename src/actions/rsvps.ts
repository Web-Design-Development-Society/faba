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

  /**
   * I'm in for all upcoming (REC-04): going to every upcoming date of the series that activity
   * `activity_id` is in, and to the dates it makes later. Returns how many dates were added.
   */
  joinSeries: defineAction({
    accept: 'form',
    input: z.object({ activity_id: z.uuid() }),
    handler: async ({ activity_id }, { locals }) => {
      if (!locals.user) throw new ActionError({ code: 'UNAUTHORIZED' });

      const { data: dates, error } = await locals.supabase.rpc('join_series', { activity_id });
      if (error) throw new ActionError(actionErrorFor(error));
      return { activity_id, dates };
    },
  }),

  /** Leave series (REC-04), which takes the member out of its upcoming dates. */
  leaveSeries: defineAction({
    accept: 'form',
    input: z.object({ activity_id: z.uuid() }),
    handler: async ({ activity_id }, { locals }) => {
      if (!locals.user) throw new ActionError({ code: 'UNAUTHORIZED' });

      const { data: dates, error } = await locals.supabase.rpc('leave_series', { activity_id });
      if (error) throw new ActionError(actionErrorFor(error));
      return { activity_id, dates };
    },
  }),
};
