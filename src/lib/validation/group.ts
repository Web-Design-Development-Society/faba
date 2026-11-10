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
