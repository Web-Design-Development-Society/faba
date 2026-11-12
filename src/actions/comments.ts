// Comment Actions. Each checks who's signed in, and post_comment() and delete_comment() check every
// rule again (ADR-004).
import { ActionError, defineAction } from 'astro:actions';
import { actionErrorFor } from '../lib/server/errors';
import { commentRemoval, newComment } from '../lib/validation/comment';

export const comments = {
  /** Posting a comment on an activity (ACT-12). Returns the comment's id. */
  post: defineAction({
    accept: 'form',
    input: newComment,
    handler: async ({ activity_id, body }, { locals }) => {
      if (!locals.user) throw new ActionError({ code: 'UNAUTHORIZED' });

      const { data, error } = await locals.supabase.rpc('post_comment', { activity_id, body });
      if (error) throw new ActionError(actionErrorFor(error));
      return { comment_id: data, activity_id };
    },
  }),

  /** Deleting your own comment (ACT-12). */
  remove: defineAction({
    accept: 'form',
    input: commentRemoval,
    handler: async ({ comment_id }, { locals }) => {
      if (!locals.user) throw new ActionError({ code: 'UNAUTHORIZED' });

      const { error } = await locals.supabase.rpc('delete_comment', { comment_id });
      if (error) throw new ActionError(actionErrorFor(error));
      return { comment_id };
    },
  }),
};
