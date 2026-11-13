// Notification Actions (NOTIF-01). Each checks who's signed in, and Postgres marks only the
// member's own notifications read (ADR-004).
import { ActionError, defineAction } from 'astro:actions';
import { SITE_URL } from 'astro:env/server';
import { z } from 'astro/zod';
import { PREFERENCE_TYPES } from '../lib/notifications';
import { actionErrorFor } from '../lib/server/errors';
import { openedHref } from '../lib/server/notifications';
import { isPushService } from '../lib/server/push/webpush';

/** A device's push subscription, as the browser's PushSubscription.toJSON() gives it (NOTIF-20). */
const device = z.object({
  endpoint: z
    .url()
    .max(1000)
    .refine((endpoint) => isPushService(endpoint, new URL(SITE_URL).hostname === 'localhost'), {
      message: "This browser's push service isn't supported.",
    }),
  p256dh: z.string().regex(/^[A-Za-z0-9_-]{87}$/),
  auth: z.string().regex(/^[A-Za-z0-9_-]{22}$/),
});

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
      return { href: await openedHref(locals.supabase, id) };
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

  /** Turns push on for this device (NOTIF-20). The page's script sends its subscription. */
  savePushDevice: defineAction({
    accept: 'json',
    input: device,
    handler: async ({ endpoint, p256dh, auth }, { locals }) => {
      if (!locals.user) throw new ActionError({ code: 'UNAUTHORIZED' });

      const { error } = await locals.supabase.rpc('save_push_subscription', {
        endpoint,
        p256dh,
        auth_secret: auth,
      });
      if (error) throw new ActionError(actionErrorFor(error));
      return { saved: true };
    },
  }),

  /** Turns push off for this device (NOTIF-20). */
  removePushDevice: defineAction({
    accept: 'json',
    input: z.object({ endpoint: z.url().max(1000) }),
    handler: async ({ endpoint }, { locals }) => {
      if (!locals.user) throw new ActionError({ code: 'UNAUTHORIZED' });

      const { error } = await locals.supabase.rpc('remove_push_subscription', { endpoint });
      if (error) throw new ActionError(actionErrorFor(error));
      return { removed: true };
    },
  }),

  /**
   * Saves which types push to the member's devices (NOTIF-20). The form posts the types that are on.
   * Cancellations always push.
   */
  savePushPreferences: defineAction({
    accept: 'form',
    input: z.object({ push: z.array(z.string()).max(PREFERENCE_TYPES.length).default([]) }),
    handler: async ({ push }, { locals }) => {
      if (!locals.user) throw new ActionError({ code: 'UNAUTHORIZED' });

      const { error } = await locals.supabase.rpc('set_push_preferences', {
        turned_on: PREFERENCE_TYPES.filter((type) => push.includes(type)),
        turned_off: PREFERENCE_TYPES.filter((type) => !push.includes(type)),
      });
      if (error) throw new ActionError(actionErrorFor(error));
      return { saved: true };
    },
  }),
};
