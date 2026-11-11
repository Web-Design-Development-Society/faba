// Interest groups (GRP-01, design document section 8.7). create_group() checks every rule again.
import { z } from 'astro/zod';

export const GROUP = {
  name: { min: 3, max: 60 },
  description: { max: 1000 },
  /** Groups a member can start in 30 days. */
  perMonth: 3,
} as const;

/** The Start a group form's fields. The output is create_group()'s arguments. */
export const newGroup = z.object({
  idempotency_key: z.uuid(),
  name: z
    .string({ error: 'Add a name.' })
    .trim()
    .min(GROUP.name.min, `Use at least ${GROUP.name.min} characters.`)
    .max(GROUP.name.max, `Use ${GROUP.name.max} characters or fewer.`),
  category_id: z.string({ error: 'Choose a category.' }),
  description: z
    .string()
    .trim()
    .max(GROUP.description.max, `Use ${GROUP.description.max} characters or fewer.`)
    .optional(),
  join_policy: z.enum(['open', 'approval'], { error: 'Choose who can join.' }).default('open'),
});

/** A member of a group, for an organizer to approve, decline, remove or change the role of (GRP-05). */
export const groupMember = z.object({ group_id: z.uuid(), user_id: z.uuid() });

/** Making a member an organizer, or a member again (GRP-05). */
export const groupRole = groupMember.extend({
  role: z.enum(['organizer', 'member'], { error: 'Choose a role.' }),
});

/**
 * Handing a group on to one of its members (GRP-05). A moderator gives a reason, which goes to the
 * audit log, and transfer_group() checks it.
 */
export const groupTransfer = z.object({
  group_id: z.uuid(),
  user_id: z.uuid({ error: 'Pick the new owner.' }),
  reason: z
    .string()
    .trim()
    .max(500, 'Use 500 characters or fewer for the reason.')
    .optional()
    .transform((reason) => reason || undefined),
});
