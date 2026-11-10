// Activity Actions. Each checks who's signed in, and Postgres checks every rule again (ADR-004).
import { ActionError, defineAction } from 'astro:actions';
import { z } from 'astro/zod';
import type { Json } from '../lib/db.types';
import { actionErrorFor } from '../lib/server/errors';
import {
  activityChanges,
  cancellation,
  descriptionChange,
  newActivity,
  restoration,
  ACTIVITY,
} from '../lib/validation/activity';
import { newUpdate } from '../lib/validation/update';

/** Sets activity `id`'s tags (SRCH-03). Returns its id. */
async function setTags(locals: App.Locals, id: string, tags: string[]) {
  const { error } = await locals.supabase.rpc('set_activity_tags', {
    activity_id: id,
    tag_ids: tags,
  });
  if (error) throw new ActionError(actionErrorFor(error));
  return { id };
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
   * Posting an activity (ACT-03), then its tags (SRCH-03). If the tags fail, posting again finds
   * the activity by its idempotency key and sets them. Returns its id.
   */
  create: defineAction({
    accept: 'form',
    input: newActivity,
    handler: async ({ tags, ...activity }, { locals }) => {
      if (!locals.user) throw new ActionError({ code: 'UNAUTHORIZED' });

      const { data: id, error } = await locals.supabase.rpc('create_activity', activity);
      if (error) throw new ActionError(actionErrorFor(error));
      return tags?.length ? setTags(locals, id, tags) : { id };
    },
  }),

  /** Editing an activity (ACT-04). An optional field left empty is cleared. Returns its id. */
  update: defineAction({
    accept: 'form',
    input: activityChanges,
    handler: async ({ id, version, tags, ...activity }, { locals }) => {
      await update(locals, id, version, {
        ...activity,
        description: activity.description ?? null,
        ends_at: activity.ends_at ?? null,
        cost_note: activity.cost_note ?? null,
        private_details: activity.private_details ?? null,
        capacity: activity.capacity ?? null,
        guests_allowed: activity.guests_allowed ?? false,
        max_guests_per_rsvp: activity.max_guests_per_rsvp ?? ACTIVITY.guests.max,
      });
      return setTags(locals, id, tags ?? []);
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
};
