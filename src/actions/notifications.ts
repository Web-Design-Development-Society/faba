// Notification Actions (NOTIF-01). Each checks who's signed in, and Postgres marks only the
// member's own notifications read (ADR-004).
import { ActionError, defineAction } from 'astro:actions';
import { z } from 'astro/zod';
import { actionErrorFor } from '../lib/server/errors';

export const notifications = {
  /** Opening a notification marks it read. Returns where it goes: its activity, if it has one. */
  open: defineAction({
    accept: 'form',
    input: z.object({ id: z.uuid() }),
    handler: async ({ id }, { locals }) => {
      if (!locals.user) throw new ActionError({ code: 'UNAUTHORIZED' });

      const { error } = await locals.supabase.rpc('mark_notifications_read', { ids: [id] });
      if (error) throw new ActionError(actionErrorFor(error));
      const { data } = await locals.supabase
        .from('notifications')
        .select('activity_id')
        .eq('id', id)
        .maybeSingle();
      return { href: data?.activity_id ? `/activities/${data.activity_id}` : '/notifications' };
    },
  }),

  /**
   * Mute updates (NOTIF-08): no more changes, updates, new attendees or reminders for the
   * activity, but cancellations still come. With `muted` false, it unmutes.
   */
  mute: defineAction({
    accept: 'form',
    input: z.object({ activity_id: z.uuid(), muted: z.boolean() }),
    handler: async ({ activity_id, muted }, { locals }) => {
      if (!locals.user) throw new ActionError({ code: 'UNAUTHORIZED' });

      const { error } = await locals.supabase.rpc('mute_activity', { activity_id, muted });
      if (error) throw new ActionError(actionErrorFor(error));
      return { muted };
    },
  }),

  /** Mark all read. Returns how many were unread. */
  readAll: defineAction({
    accept: 'form',
    handler: async (_, { locals }) => {
      if (!locals.user) throw new ActionError({ code: 'UNAUTHORIZED' });

      const { data, error } = await locals.supabase.rpc('mark_notifications_read', {});
      if (error) throw new ActionError(actionErrorFor(error));
      return { marked: data };
    },
  }),
};
