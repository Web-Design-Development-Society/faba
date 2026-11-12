// Moderation Actions. Each checks who's signed in, and Postgres checks that they moderate and every
// rule again (ADR-004).
import { ActionError, defineAction } from 'astro:actions';
import { actionErrorFor } from '../lib/server/errors';
import {
  activityHide,
  activityModeration,
  activityTransfer,
  commentHide,
  commentModeration,
  imageHide,
  imageModeration,
  dismissal,
  memberModeration,
  memberSuspension,
  moderatorNote,
  reasonFor,
  updateHide,
  updateModeration,
} from '../lib/validation/moderation';

// The reason is required: a typed one, or the common one picked (MOD-08).
const required = (input: { reason?: string; template?: string }) => {
  const reason = reasonFor(input);
  if (!reason) {
    throw new ActionError({
      code: 'BAD_REQUEST',
      message: 'Give a reason. It goes to the audit log.',
    });
  }
  return reason;
};

export const moderation = {
  /** Dismissing a report from the queue, with a reason (MOD-02). Returns its id. */
  dismiss: defineAction({
    accept: 'form',
    input: dismissal,
    handler: async ({ report_id, ...input }, { locals }) => {
      if (!locals.user) throw new ActionError({ code: 'UNAUTHORIZED' });

      const reason = required(input);
      const { error } = await locals.supabase.rpc('dismiss_report', { report_id, reason });
      if (error) throw new ActionError(actionErrorFor(error));
      return { report_id };
    },
  }),

  /** Hiding an activity, with the reason its organizer sees (MOD-03). Returns its id. */
  hide: defineAction({
    accept: 'form',
    input: activityHide,
    handler: async ({ activity_id, ...input }, { locals }) => {
      if (!locals.user) throw new ActionError({ code: 'UNAUTHORIZED' });

      const reason = required(input);
      const { error } = await locals.supabase.rpc('moderate_hide', { activity_id, reason });
      if (error) throw new ActionError(actionErrorFor(error));
      return { activity_id };
    },
  }),

  /** Unhiding an activity, with a reason (MOD-03). Returns its id. */
  unhide: defineAction({
    accept: 'form',
    input: activityModeration,
    handler: async ({ activity_id, reason }, { locals }) => {
      if (!locals.user) throw new ActionError({ code: 'UNAUTHORIZED' });

      const { error } = await locals.supabase.rpc('moderate_unhide', { activity_id, reason });
      if (error) throw new ActionError(actionErrorFor(error));
      return { activity_id };
    },
  }),

  /** Hiding an organizer's update, with the reason its author sees (NOTIF-04). Returns its id. */
  hideUpdate: defineAction({
    accept: 'form',
    input: updateHide,
    handler: async ({ update_id, ...input }, { locals }) => {
      if (!locals.user) throw new ActionError({ code: 'UNAUTHORIZED' });

      const reason = required(input);
      const { error } = await locals.supabase.rpc('moderate_hide_update', { update_id, reason });
      if (error) throw new ActionError(actionErrorFor(error));
      return { update_id };
    },
  }),

  /** Unhiding an organizer's update, with a reason (NOTIF-04). Returns its id. */
  unhideUpdate: defineAction({
    accept: 'form',
    input: updateModeration,
    handler: async ({ update_id, reason }, { locals }) => {
      if (!locals.user) throw new ActionError({ code: 'UNAUTHORIZED' });

      const { error } = await locals.supabase.rpc('moderate_unhide_update', { update_id, reason });
      if (error) throw new ActionError(actionErrorFor(error));
      return { update_id };
    },
  }),

  /** Hiding a comment, with the reason its author sees (ACT-12). Returns its id. */
  hideComment: defineAction({
    accept: 'form',
    input: commentHide,
    handler: async ({ comment_id, ...input }, { locals }) => {
      if (!locals.user) throw new ActionError({ code: 'UNAUTHORIZED' });

      const reason = required(input);
      const { error } = await locals.supabase.rpc('moderate_hide_comment', { comment_id, reason });
      if (error) throw new ActionError(actionErrorFor(error));
      return { comment_id };
    },
  }),

  /** Unhiding a comment, with a reason (ACT-12). Returns its id. */
  unhideComment: defineAction({
    accept: 'form',
    input: commentModeration,
    handler: async ({ comment_id, reason }, { locals }) => {
      if (!locals.user) throw new ActionError({ code: 'UNAUTHORIZED' });

      const { error } = await locals.supabase.rpc('moderate_unhide_comment', {
        comment_id,
        reason,
      });
      if (error) throw new ActionError(actionErrorFor(error));
      return { comment_id };
    },
  }),

  /** Hiding a picture, with the reason its uploader sees (MEDIA-01). Returns its id. */
  hideImage: defineAction({
    accept: 'form',
    input: imageHide,
    handler: async ({ image_id, ...input }, { locals }) => {
      if (!locals.user) throw new ActionError({ code: 'UNAUTHORIZED' });

      const reason = required(input);
      const { error } = await locals.supabase.rpc('moderate_hide_image', { image_id, reason });
      if (error) throw new ActionError(actionErrorFor(error));
      return { image_id };
    },
  }),

  /** Unhiding a picture, with a reason (MEDIA-01). Returns its id. */
  unhideImage: defineAction({
    accept: 'form',
    input: imageModeration,
    handler: async ({ image_id, reason }, { locals }) => {
      if (!locals.user) throw new ActionError({ code: 'UNAUTHORIZED' });

      const { error } = await locals.supabase.rpc('moderate_unhide_image', { image_id, reason });
      if (error) throw new ActionError(actionErrorFor(error));
      return { image_id };
    },
  }),

  /**
   * Giving an ineligible organizer's upcoming activity to a member who's going, with a reason
   * (AUTH-05). Returns its id.
   */
  transfer: defineAction({
    accept: 'form',
    input: activityTransfer,
    handler: async ({ activity_id, to_user, reason }, { locals }) => {
      if (!locals.user) throw new ActionError({ code: 'UNAUTHORIZED' });

      const { error } = await locals.supabase.rpc('moderate_transfer_activity', {
        activity_id,
        to_user,
        reason,
      });
      if (error) throw new ActionError(actionErrorFor(error));
      return { activity_id };
    },
  }),

  /** Cancelling an ineligible organizer's upcoming activity, with a reason (AUTH-05). */
  cancel: defineAction({
    accept: 'form',
    input: activityModeration,
    handler: async ({ activity_id, reason }, { locals }) => {
      if (!locals.user) throw new ActionError({ code: 'UNAUTHORIZED' });

      const { error } = await locals.supabase.rpc('moderate_cancel_activity', {
        activity_id,
        reason,
      });
      if (error) throw new ActionError(actionErrorFor(error));
      return { activity_id };
    },
  }),

  /** Suspending a member, with a reason (MOD-04). Returns their id. */
  suspend: defineAction({
    accept: 'form',
    input: memberSuspension,
    handler: async ({ user_id, ...input }, { locals }) => {
      if (!locals.user) throw new ActionError({ code: 'UNAUTHORIZED' });

      const reason = required(input);
      const { error } = await locals.supabase.rpc('suspend_member', { user_id, reason });
      if (error) throw new ActionError(actionErrorFor(error));
      return { user_id };
    },
  }),

  /** Reinstating a suspended member, with a reason (MOD-04). Returns their id. */
  reinstate: defineAction({
    accept: 'form',
    input: memberModeration,
    handler: async ({ user_id, reason }, { locals }) => {
      if (!locals.user) throw new ActionError({ code: 'UNAUTHORIZED' });

      const { error } = await locals.supabase.rpc('reinstate_member', { user_id, reason });
      if (error) throw new ActionError(actionErrorFor(error));
      return { user_id };
    },
  }),

  /** A moderator's note on what's reported (MOD-08). Returns its id. */
  addNote: defineAction({
    accept: 'form',
    input: moderatorNote,
    handler: async ({ target_type, target_id, body }, { locals }) => {
      if (!locals.user) throw new ActionError({ code: 'UNAUTHORIZED' });

      const { data, error } = await locals.supabase.rpc('add_moderator_note', {
        target_type,
        target_id,
        body,
      });
      if (error) throw new ActionError(actionErrorFor(error));
      return { note_id: data };
    },
  }),
};
