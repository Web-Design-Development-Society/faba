// Profile Actions. Each checks who's signed in, and Postgres checks every rule again (ADR-004).
import { ActionError, defineAction } from 'astro:actions';
import { z } from 'astro/zod';
import { displayName } from '../lib/validation/profile';

export const profile = {
  /** Welcome (PROF-01): the display name, the photo or initials, and accepting the guidelines. */
  acceptGuidelines: defineAction({
    accept: 'form',
    input: z.object({
      version: z.number().int(),
      display_name: displayName,
      use_initials: z.boolean(),
      agree: z.boolean().refine((agreed) => agreed, 'Check the box to agree to the guidelines.'),
    }),
    handler: async ({ version, display_name, use_initials }, { locals }) => {
      if (!locals.user) throw new ActionError({ code: 'UNAUTHORIZED' });

      const { error } = await locals.supabase.rpc('accept_guidelines', {
        version,
        display_name,
        use_initials,
      });
      if (error?.message === 'GUIDELINES_CHANGED') {
        throw new ActionError({
          code: 'CONFLICT',
          message: 'The guidelines changed while you were reading. Please read them again.',
        });
      }
      if (error) {
        throw new ActionError({
          code: 'INTERNAL_SERVER_ERROR',
          message: "Your details couldn't be saved. Please try again.",
        });
      }
    },
  }),
};
