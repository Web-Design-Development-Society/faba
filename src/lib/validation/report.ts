// Reporting an activity, a member (MOD-01) or an organizer's update (NOTIF-04). The reasons and the
// note's limit match the reports table's CHECK constraints, and report_content() checks the rest.
import { z } from 'astro/zod';

/** The reasons a member can choose, in the order the form shows them. */
export const REASONS = {
  inappropriate: 'Inappropriate',
  spam: 'Spam / commercial',
  unsafe: 'Unsafe',
  other: 'Other',
};

export const NOTE_MAX = 500;

export const newReport = z.object({
  target_type: z.enum(['activity', 'profile', 'activity_update', 'group', 'comment', 'image']),
  target_id: z.uuid(),
  reason: z.enum(Object.keys(REASONS) as [keyof typeof REASONS], { error: 'Choose a reason.' }),
  note: z
    .string()
    .trim()
    .max(NOTE_MAX, `Use ${NOTE_MAX} characters or fewer for the note.`)
    .optional(),
});
