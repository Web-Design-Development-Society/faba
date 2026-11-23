// Activity Actions. Each checks who's signed in, and Postgres checks every rule again (ADR-004).
import { ActionError, defineAction } from 'astro:actions';
import { z } from 'astro/zod';
import type { Json } from '../lib/db.types';
import { actionErrorFor } from '../lib/server/errors';
import { drop, refusal, store } from '../lib/server/pictures';
import {
  activityChanges,
  cancellation,
  descriptionChange,
  newActivity,
  restoration,
  ACTIVITY,
} from '../lib/validation/activity';
import { newUpdate } from '../lib/validation/update';

/**
 * Stores the picture chosen while posting and makes it activity `id`'s cover (MEDIA-02). For a date
 * in a series, every date shows it, and the ones the series adds later too. The activity is posted
 * either way, so this says whether the picture saved rather than throwing.
 */
async function saveCover(
  locals: App.Locals,
  id: string,
  picture: File,
  copies: { thumb?: File; medium?: File },
  alt: string
): Promise<'saved' | 'failed'> {
  let key: string | null = null;
  try {
    const stored = await store('activities', picture, copies);
    key = stored.key;
    const { error } = await locals.supabase.rpc('set_activity_cover', {
      activity_id: id,
      r2_key: stored.key,
      content_type: stored.type,
      bytes: stored.bytes,
      alt,
    });
    if (error) throw error;
    key = null;
    // A one-off activity has no series, and this does nothing.
    const { error: shared } = await locals.supabase.rpc('share_cover_with_series', {
      activity_id: id,
    });
    if (shared) console.warn(JSON.stringify({ cover: 'not shared', error: shared.message }));
    return 'saved';
  } catch (error) {
    console.warn(
      JSON.stringify({ cover: 'failed', error: error instanceof Error ? error.message : error })
    );
    if (key) await drop(key);
    return 'failed';
  }
}

/** Saves `patch` to activity `id`, if it's still at `version` (ACT-04). Returns its id. */
async function update(locals: App.Locals, id: string, version: number, patch: Json) {
  if (!locals.user) throw new ActionError({ code: 'UNAUTHORIZED' });

  const { error } = await locals.supabase.rpc('update_activity', {
    activity_id: id,
    patch,
    expected_version: version,
  });
  if (error) throw new ActionError(actionErrorFor(error));
  return { id };
}

export const activities = {
  /**
   * Posting an activity (ACT-03). Returns its id. One that repeats is a series, and the id is its
   * first date's (REC-01). Activities have no tags since UI-09.
   */
  create: defineAction({
    accept: 'form',
    input: newActivity,
    handler: async (
      { repeats, until_date, picture, thumb, medium, alt, ...activity },
      { locals }
    ) => {
      if (!locals.user) throw new ActionError({ code: 'UNAUTHORIZED' });

      // MEDIA-02. A picture that won't do is caught before anything is posted.
      const cover = picture && picture.size > 0 ? picture : null;
      const refused = cover && (await refusal(cover));
      if (refused) {
        throw new ActionError({
          code: 'BAD_REQUEST',
          message:
            refused === 'upload_too_big'
              ? 'Use a picture under 2 MB.'
              : 'Use a JPEG, PNG or WebP picture.',
        });
      }

      let id: string;
      if (repeats !== 'none') {
        // eslint-disable-next-line @typescript-eslint/no-unused-vars -- A series isn't a copy.
        const { copied_from_id, ...series } = activity;
        const { data, error } = await locals.supabase.rpc('create_series', {
          ...series,
          freq: repeats,
          until_date,
        });
        if (error) throw new ActionError(actionErrorFor(error));
        id = data;
      } else {
        const { data, error } = await locals.supabase.rpc('create_activity', activity);
        if (error) throw new ActionError(actionErrorFor(error));
        id = data;
      }

      if (!cover) return { id, picture: 'none' as const };
      return { id, picture: await saveCover(locals, id, cover, { thumb, medium }, alt ?? '') };
    },
  }),

  /**
   * Editing an activity (ACT-04). An optional field left empty is cleared. For a date in a series,
   * `scope` is just it, which detaches it, or it and the series' later dates (REC-02). Returns its
   * id and the scope.
   */
  update: defineAction({
    accept: 'form',
    input: activityChanges,
    handler: async ({ id, version, scope, ...activity }, { locals }) => {
      const patch = {
        ...activity,
        description: activity.description ?? null,
        ends_at: activity.ends_at ?? null,
        cost_note: activity.cost_note ?? null,
        private_details: activity.private_details ?? null,
        capacity: activity.capacity ?? null,
        guests_allowed: activity.guests_allowed ?? false,
        max_guests_per_rsvp: activity.max_guests_per_rsvp ?? ACTIVITY.guests.max,
      };

      if (scope === 'future') {
        if (!locals.user) throw new ActionError({ code: 'UNAUTHORIZED' });

        const { error } = await locals.supabase.rpc('update_series', {
          activity_id: id,
          patch,
          expected_version: version,
        });
        if (error) throw new ActionError(actionErrorFor(error));
        return { id, scope };
      }

      await update(locals, id, version, patch);
      return { id, scope };
    },
  }),

  /**
   * Editing an activity that has started, when only its description (ACT-04) and its details for
   * attendees (ACT-09) can change.
   */
  updateDescription: defineAction({
    accept: 'form',
    input: descriptionChange,
    handler: ({ id, version, description, private_details }, { locals }) =>
      update(locals, id, version, {
        description: description ?? null,
        private_details: private_details ?? null,
      }),
  }),

  /**
   * An activity's details for attendees (ACT-09), or null for anyone RLS doesn't let read them.
   * The activity page asks again when the member's answer changes, to show or hide them.
   */
  privateDetails: defineAction({
    input: z.object({ activity_id: z.uuid() }),
    handler: async ({ activity_id }, { locals }) => {
      if (!locals.user) throw new ActionError({ code: 'UNAUTHORIZED' });

      const { data, error } = await locals.supabase
        .from('activity_private_details')
        .select('details')
        .eq('activity_id', activity_id)
        .maybeSingle();
      if (error) throw new ActionError(actionErrorFor(error));
      return { details: data?.details ?? null };
    },
  }),

  /** Cancelling an activity (ACT-05). It stays, marked cancelled. Returns its id. */
  cancel: defineAction({
    accept: 'form',
    input: cancellation,
    handler: async ({ id, reason }, { locals }) => {
      if (!locals.user) throw new ActionError({ code: 'UNAUTHORIZED' });

      const { error } = await locals.supabase.rpc('cancel_activity', { activity_id: id, reason });
      if (error) throw new ActionError(actionErrorFor(error));
      return { id };
    },
  }),

  /** Restoring a cancelled activity, until it starts (ACT-05). Returns its id. */
  restore: defineAction({
    accept: 'form',
    input: restoration,
    handler: async ({ id }, { locals }) => {
      if (!locals.user) throw new ActionError({ code: 'UNAUTHORIZED' });

      const { error } = await locals.supabase.rpc('restore_activity', { activity_id: id });
      if (error) throw new ActionError(actionErrorFor(error));
      return { id };
    },
  }),

  /**
   * Marking an activity as a FABA board activity, or not (MOD-07). Only an admin who organizes it
   * can. Returns its id and whether it is one.
   */
  setBoard: defineAction({
    accept: 'form',
    input: z.object({ id: z.uuid(), board: z.boolean() }),
    handler: async ({ id, board }, { locals }) => {
      if (!locals.user) throw new ActionError({ code: 'UNAUTHORIZED' });

      const { error } = await locals.supabase.rpc('set_board_activity', { activity_id: id, board });
      if (error) throw new ActionError(actionErrorFor(error));
      return { id, board };
    },
  }),

  /** Announcing a board activity to every member, once (MOD-07). Returns its id. */
  announce: defineAction({
    accept: 'form',
    input: z.object({ id: z.uuid() }),
    handler: async ({ id }, { locals }) => {
      if (!locals.user) throw new ActionError({ code: 'UNAUTHORIZED' });

      const { error } = await locals.supabase.rpc('announce_activity', { activity_id: id });
      if (error) throw new ActionError(actionErrorFor(error));
      return { id };
    },
  }),

  /**
   * Posting an update to everyone going or maybe (NOTIF-04). Posting again with the same
   * idempotency key returns the update already posted. Returns the activity's id.
   */
  postUpdate: defineAction({
    accept: 'form',
    input: newUpdate,
    handler: async ({ activity_id, body, idempotency_key }, { locals }) => {
      if (!locals.user) throw new ActionError({ code: 'UNAUTHORIZED' });

      const { error } = await locals.supabase.rpc('post_activity_update', {
        activity_id,
        body,
        idempotency_key,
      });
      if (error) throw new ActionError(actionErrorFor(error));
      return { id: activity_id };
    },
  }),

  /**
   * Makes `user_id`, a member, a co-organizer of `activity_id` (ACT-10), who can edit and cancel
   * it. Up to 3. Returns the activity's id.
   */
  addCoOrganizer: defineAction({
    accept: 'form',
    input: z.object({ activity_id: z.uuid(), user_id: z.uuid() }),
    handler: async ({ activity_id, user_id }, { locals }) => {
      if (!locals.user) throw new ActionError({ code: 'UNAUTHORIZED' });

      const { error } = await locals.supabase.rpc('add_co_organizer', { activity_id, user_id });
      if (error) throw new ActionError(actionErrorFor(error));
      return { id: activity_id };
    },
  }),

  /** Removes co-organizer `user_id` from `activity_id` (ACT-10). Returns the activity's id. */
  removeCoOrganizer: defineAction({
    accept: 'form',
    input: z.object({ activity_id: z.uuid(), user_id: z.uuid() }),
    handler: async ({ activity_id, user_id }, { locals }) => {
      if (!locals.user) throw new ActionError({ code: 'UNAUTHORIZED' });

      const { error } = await locals.supabase.rpc('remove_co_organizer', { activity_id, user_id });
      if (error) throw new ActionError(actionErrorFor(error));
      return { id: activity_id };
    },
  }),
};
