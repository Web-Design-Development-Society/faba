// Moderation Actions. Each checks who's signed in, and Postgres checks that they moderate and every
// rule again (ADR-004).
import { ActionError, defineAction } from 'astro:actions';
import { actionErrorFor } from '../lib/server/errors';
import {
  activityModeration,
  activityTransfer,
  dismissal,
  memberModeration,
} from '../lib/validation/moderation';

export const moderation = {
  /** Dismissing a report from the queue, with a reason (MOD-02). Returns its id. */
  dismiss: defineAction({
    accept: 'form',
    input: dismissal,
    handler: async ({ report_id, reason }, { locals }) => {
      if (!locals.user) throw new ActionError({ code: 'UNAUTHORIZED' });

      const { error } = await locals.supabase.rpc('dismiss_report', { report_id, reason });
      if (error) throw new ActionError(actionErrorFor(error));
      return { report_id };
    },
  }),

  /** Hiding an activity, with the reason its organizer sees (MOD-03). Returns its id. */
  hide: defineAction({
    accept: 'form',
    input: activityModeration,
    handler: async ({ activity_id, reason }, { locals }) => {
      if (!locals.user) throw new ActionError({ code: 'UNAUTHORIZED' });

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
    input: memberModeration,
    handler: async ({ user_id, reason }, { locals }) => {
      if (!locals.user) throw new ActionError({ code: 'UNAUTHORIZED' });

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
};
