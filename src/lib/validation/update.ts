// Posting an update to an activity's attendees (NOTIF-04). The limit matches the activity_updates
// table's CHECK constraint, and post_activity_update() checks the rest.
import { z } from 'astro/zod';

export const UPDATE_MAX = 500;

export const newUpdate = z.object({
  activity_id: z.uuid(),
  body: z
    .string()
    .trim()
    .min(1, 'Write your update.')
    .max(UPDATE_MAX, `Use ${UPDATE_MAX} characters or fewer.`),
  idempotency_key: z.uuid(),
});
