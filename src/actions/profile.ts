// Profile Actions. Each checks who's signed in, and Postgres checks every rule again (ADR-004).
import { ActionError, defineAction } from 'astro:actions';
import { z } from 'astro/zod';
import { deleteAuthUser } from '../lib/server/admin';
import { actionErrorFor } from '../lib/server/errors';
import { accountDeletion, displayName, profileChanges } from '../lib/validation/profile';

const NOT_SAVED = "Your profile couldn't be saved. Please try again.";

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

  /**
   * Editing the profile (PROF-02). Members update their own columns directly, which column grants
   * and Row Level Security limit (ADR-004). Faculty type is in the private profile.
   */
  update: defineAction({
    accept: 'form',
    input: profileChanges,
    handler: async ({ faculty_type, department, bio, interests, ...changes }, { locals }) => {
      const { supabase, user } = locals;
      if (!user) throw new ActionError({ code: 'UNAUTHORIZED' });

      // Only categories the form offers, once each.
      const { data: categories } = await supabase
        .from('categories')
        .select('id')
        .eq('is_active', true);
      const offered = new Set(categories?.map(({ id }) => id));

      const { data, error } = await supabase
        .from('profiles')
        .update({
          ...changes,
          department: department || null,
          bio: bio || null,
          interests: [...new Set(interests)].filter((id) => offered.has(id)),
        })
        .eq('id', user.id)
        .select('id');
      if (error) throw new ActionError({ code: 'INTERNAL_SERVER_ERROR', message: NOT_SAVED });
      // Row Level Security left the row out: the member isn't active.
      if (!data.length) {
        throw new ActionError({
          code: 'FORBIDDEN',
          message: 'Only active members can edit their profile.',
        });
      }

      const { error: privateError } = await supabase
        .from('profile_private')
        .update({ faculty_type: faculty_type ?? null })
        .eq('user_id', user.id);
      if (privateError) {
        throw new ActionError({ code: 'INTERNAL_SERVER_ERROR', message: NOT_SAVED });
      }
    },
  }),

  /**
   * Deleting the account (PROF-05). delete_my_account() cancels the member's upcoming activities,
   * removes their RSVPs and logs it. Then the admin API deletes their auth user, and the foreign
   * keys remove their profile. Both steps can run again, so a failure can be retried. The page
   * signs them out.
   */
  deleteAccount: defineAction({
    accept: 'form',
    input: accountDeletion,
    handler: async (_input, { locals }) => {
      const { supabase, user } = locals;
      if (!user) throw new ActionError({ code: 'UNAUTHORIZED' });

      const { error } = await supabase.rpc('delete_my_account');
      if (error) throw new ActionError(actionErrorFor(error));

      const { error: authError } = await deleteAuthUser(user.id);
      if (authError) {
        console.error(JSON.stringify({ action: 'deleteAccount', message: authError.message }));
        throw new ActionError({
          code: 'INTERNAL_SERVER_ERROR',
          message: "Your account couldn't be deleted. Please try again.",
        });
      }
    },
  }),
};
