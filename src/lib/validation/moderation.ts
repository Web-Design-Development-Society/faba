// Moderators' actions on the reports queue (MOD-02). Each needs a reason, which goes to the audit
// log (MOD-05). The limit matches the reports and audit_log tables' CHECK constraints. Hiding,
// suspending and dismissing can also take a common reason from a list (MOD-08), which fills in the
// reason when the moderator doesn't type one. The reason is required either way.
import { z } from 'astro/zod';

export const MODERATION_REASON_MAX = 500;
export const MODERATION_NOTE_MAX = 500;

/** The common reasons a moderator can pick (MOD-08), in the order the sheet shows them. */
export const REASON_TEMPLATES = {
  off_topic: 'Off topic for FABA',
  misleading: 'Misleading details',
  harassment: 'Harassment or hostile messages',
  spam: 'Spam or self-promotion',
  unsafe: 'Unsafe to meet',
  repeated: 'Repeated guideline breaches',
  not_a_problem: 'Not a problem after review',
} as const;

export type ReasonTemplate = keyof typeof REASON_TEMPLATES;

const reason = z
  .string({ error: 'Give a reason. It goes to the audit log.' })
  .trim()
  .min(1, 'Give a reason. It goes to the audit log.')
  .max(MODERATION_REASON_MAX, `Use ${MODERATION_REASON_MAX} characters or fewer for the reason.`);

// A blank choice from the list counts as none.
const template = z
  .enum(Object.keys(REASON_TEMPLATES) as [ReasonTemplate, ...ReasonTemplate[]])
  .or(z.literal(''))
  .optional();

/** A reason typed in, or a common one picked. The handler checks one of them is there. */
const reasonOrTemplate = {
  reason: z
    .string()
    .trim()
    .max(MODERATION_REASON_MAX, `Use ${MODERATION_REASON_MAX} characters or fewer for the reason.`)
    .optional(),
  template,
};

/** The reason an action goes with: what was typed, or the common one picked. Blank if neither. */
export function reasonFor(input: { reason?: string; template?: string }): string {
  const typed = input.reason?.trim();
  if (typed) return typed;
  const picked = input.template ? REASON_TEMPLATES[input.template as ReasonTemplate] : undefined;
  return picked ?? '';
}

/** Dismissing a report: nothing needed doing. */
export const dismissal = z.object({ report_id: z.uuid(), ...reasonOrTemplate });

/** Hiding an activity (MOD-03). */
export const activityHide = z.object({ activity_id: z.uuid(), ...reasonOrTemplate });

/** Unhiding an activity, or cancelling an ineligible organizer's (MOD-03, AUTH-05). */
export const activityModeration = z.object({ activity_id: z.uuid(), reason });

/** Giving an ineligible organizer's activity to a member who's going (AUTH-05). */
export const activityTransfer = activityModeration.extend({
  to_user: z.uuid({ error: 'Pick the new host.' }),
});

/** Hiding an organizer's update (NOTIF-04). */
export const updateHide = z.object({ update_id: z.uuid(), ...reasonOrTemplate });

/** Unhiding an organizer's update (NOTIF-04). */
export const updateModeration = z.object({ update_id: z.uuid(), reason });

/** Hiding a comment, with the reason its author sees (ACT-12). */
export const commentHide = z.object({ comment_id: z.uuid(), ...reasonOrTemplate });

/** Unhiding a comment, with a reason (ACT-12). */
export const commentModeration = z.object({ comment_id: z.uuid(), reason });

/** Suspending a member (MOD-04). */
export const memberSuspension = z.object({ user_id: z.uuid(), ...reasonOrTemplate });

/** Reinstating a member (MOD-04). */
export const memberModeration = z.object({ user_id: z.uuid(), reason });

/** A moderator's note on what's reported (MOD-08). */
export const moderatorNote = z.object({
  target_type: z.enum(['activity', 'profile', 'activity_update', 'group', 'comment']),
  target_id: z.uuid(),
  body: z
    .string({ error: 'Write a note.' })
    .trim()
    .min(1, 'Write a note.')
    .max(MODERATION_NOTE_MAX, `Use ${MODERATION_NOTE_MAX} characters or fewer for the note.`),
});
