// Email preferences (NOTIF-13): which types reach a member by email, their quiet hours, and how far
// ahead reminders come. The lead times match the reminder_lead_hours CHECK constraint.
import { z } from 'astro/zod';
import { PREFERENCE_TYPES } from '../notifications';

export const REMINDER_LEAD_HOURS = [1, 2, 6, 24] as const;

// A time from a time input, as HH:MM, in Boise time.
const clock = z.string({ error: 'Pick a time.' }).regex(/^\d{2}:\d{2}$/, 'Pick a time.');

/** Saving email preferences: the types that stay on by email, quiet hours and the reminder lead. */
export const channelSave = z.object({
  email: z.array(z.string()).max(PREFERENCE_TYPES.length).default([]),
  quiet_start: clock,
  quiet_end: clock,
  reminder_lead_hours: z.coerce
    .number({ error: 'Pick how far ahead reminders come.' })
    .int()
    .refine(
      (n) => (REMINDER_LEAD_HOURS as readonly number[]).includes(n),
      'Pick 1, 2, 6 or 24 hours.'
    ),
});
