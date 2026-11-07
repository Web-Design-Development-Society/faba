// Activity Actions. Each checks who's signed in, and Postgres checks every rule again (ADR-004).
import { ActionError, defineAction } from 'astro:actions';
import type { Json } from '../lib/db.types';
import { actionErrorFor } from '../lib/server/errors';
import {
  activityChanges,
  cancellation,
  descriptionChange,
  newActivity,
  restoration,
} from '../lib/validation/activity';

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
        capacity: activity.capacity ?? null,
      });
      return setTags(locals, id, tags ?? []);
    },
  }),

  /** Editing an activity that has started, when only its description can change (ACT-04). */
  updateDescription: defineAction({
    accept: 'form',
    input: descriptionChange,
    handler: ({ id, version, description }, { locals }) =>
      update(locals, id, version, { description: description ?? null }),
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
};
