// Notification Actions (NOTIF-01). Each checks who's signed in, and Postgres marks only the
// member's own notifications read (ADR-004).
import { ActionError, defineAction } from 'astro:actions';
import { z } from 'astro/zod';
import { PREFERENCE_TYPES } from '../lib/notifications';
import { actionErrorFor } from '../lib/server/errors';

export const notifications = {
  /**
   * Opening a notification marks it read. Returns where it goes: its activity, or its group, if it
   * has one. A join request opens the group's members, to approve it (GRP-02, GRP-05).
   */
  open: defineAction({
    accept: 'form',
    input: z.object({ id: z.uuid() }),
    handler: async ({ id }, { locals }) => {
      if (!locals.user) throw new ActionError({ code: 'UNAUTHORIZED' });

      const { error } = await locals.supabase.rpc('mark_notifications_read', { ids: [id] });
      if (error) throw new ActionError(actionErrorFor(error));
      const { data } = await locals.supabase
        .from('notifications')
        .select('type, activity_id, payload, group:groups(slug)')
        .eq('id', id)
        .maybeSingle();
      // A batched follow notice opens its category or group, which its payload names.
      const link = data?.type === 'new_activity' ? (data.payload as { href?: string }).href : null;
      return {
        href:
          link ??
          (data?.activity_id
            ? `/activities/${data.activity_id}`
            : data?.group
              ? `/groups/${data.group.slug}${data.type === 'group_join_request' ? '/members' : ''}`
              : '/notifications'),
      };
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

  /**
   * Saves which types the member wants (NOTIF-10). `on` lists the ones they keep. The rest are off,
   * and cancellations are always on. Returns the types that are off.
   */
  savePreferences: defineAction({
    accept: 'form',
    input: z.object({ on: z.array(z.string()).max(PREFERENCE_TYPES.length).default([]) }),
    handler: async ({ on }, { locals }) => {
      if (!locals.user) throw new ActionError({ code: 'UNAUTHORIZED' });

      const off = PREFERENCE_TYPES.filter((type) => !on.includes(type));
      const { error } = await locals.supabase.rpc('set_notification_preferences', { off });
      if (error) throw new ActionError(actionErrorFor(error));
      return { off };
    },
  }),
};
