// Posting an update to an activity's attendees (NOTIF-04), or to a group's members (GRP-04). The
// limit matches the activity_updates table's CHECK constraint, and post_activity_update() and
// post_group_update() check the rest.
import { z } from 'astro/zod';

export const UPDATE_MAX = 500;

/** Updates a group can have in 24 hours (GRP-04). */
export const GROUP_UPDATES_PER_DAY = 3;

const body = z
  .string()
  .trim()
  .min(1, 'Write your update.')
  .max(UPDATE_MAX, `Use ${UPDATE_MAX} characters or fewer.`);

export const newUpdate = z.object({ activity_id: z.uuid(), body, idempotency_key: z.uuid() });

export const newGroupUpdate = z.object({ group_id: z.uuid(), body, idempotency_key: z.uuid() });
