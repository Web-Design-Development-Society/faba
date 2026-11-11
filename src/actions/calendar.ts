// The calendar feed's link (CAL-01). The link is shown once, so the page gets it from this Action.
import { ActionError, defineAction } from 'astro:actions';
import { SITE_URL } from 'astro:env/server';
import { z } from 'astro/zod';
import { newFeedToken, hashFeedToken } from '../lib/calendar-feed';
import { actionErrorFor } from '../lib/server/errors';

export const calendar = {
  /**
   * Makes a new calendar feed link for the member, which replaces any earlier one, so the old link
   * stops working (CAL-01). Returns the full link, to show once.
   */
  resetFeed: defineAction({
    accept: 'form',
    input: z.object({}),
    handler: async (_input, { locals }) => {
      if (!locals.user) throw new ActionError({ code: 'UNAUTHORIZED' });

      const token = newFeedToken();
      const { error } = await locals.supabase.rpc('reset_calendar_feed', {
        token_hash: await hashFeedToken(token),
      });
      if (error) throw new ActionError(actionErrorFor(error));
      return { url: new URL(`/calendar/${token}.ics`, SITE_URL).href };
    },
  }),
};
