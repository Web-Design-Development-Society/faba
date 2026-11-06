// Moderators' actions on the reports queue (MOD-02). Each needs a reason, which goes to the audit
// log (MOD-05). The limit matches the reports and audit_log tables' CHECK constraints.
import { z } from 'astro/zod';

export const MODERATION_REASON_MAX = 500;

const reason = z
  .string({ error: 'Give a reason. It goes to the audit log.' })
  .trim()
  .min(1, 'Give a reason. It goes to the audit log.')
  .max(MODERATION_REASON_MAX, `Use ${MODERATION_REASON_MAX} characters or fewer for the reason.`);

/** Dismissing a report: nothing needed doing. */
export const dismissal = z.object({ report_id: z.uuid(), reason });

/** Hiding an activity, or unhiding it (MOD-03). */
export const activityModeration = z.object({ activity_id: z.uuid(), reason });

/** Giving an ineligible organizer's activity to a member who's going (AUTH-05). */
export const activityTransfer = activityModeration.extend({
  to_user: z.uuid({ error: 'Pick the new host.' }),
});

/** Suspending a member, or reinstating them (MOD-04). */
export const memberModeration = z.object({ user_id: z.uuid(), reason });
