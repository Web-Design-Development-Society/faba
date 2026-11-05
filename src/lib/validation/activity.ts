// Posting an activity (ACT-03), editing it with the same rules (ACT-04), and cancelling it
// (ACT-05). The limits match the activities table's CHECK constraints, and create_activity() and
// update_activity() check the time rules again.
import { z } from 'astro/zod';
import { rexburgInstant } from '../time';

export const ACTIVITY = {
  title: { min: 3, max: 80 },
  place: { max: 120 },
  description: { max: 2000 },
  costNote: { max: 60 },
  cancelReason: { max: 200 },
  monthsAhead: 12,
};

/** When an activity starts and, if it has an end time, ends. Both are on `date`, in Rexburg. */
export function activityTimes(date: string, startTime: string, endTime?: string) {
  return {
    startsAt: rexburgInstant(date, startTime),
    endsAt: endTime ? rexburgInstant(date, endTime) : undefined,
  };
}

/** The form's suggested start: a day from `now`, rounded up to the next half hour (section 7.7). */
export function suggestedStart(now: Date): Date {
  const halfHour = 30 * 60 * 1000;
  return new Date(Math.ceil((now.getTime() + 24 * 60 * 60 * 1000) / halfHour) * halfHour);
}

/** The latest start allowed for an activity posted at `now`. */
export function latestStart(now: Date): Date {
  const latest = new Date(now);
  latest.setUTCMonth(latest.getUTCMonth() + ACTIVITY.monthsAhead);
  return latest;
}

const isDate = (value: string) => z.iso.date().safeParse(value).success;
const isTime = (value: string) => z.iso.time().safeParse(value).success;

type Times = { date: string; start_time: string; end_time?: string };

/** The start is in the future and in the next 12 months, and the end is after it. */
function checkTimes({ date, start_time, end_time }: Times, ctx: z.RefinementCtx) {
  // A malformed date or time has its own message.
  if (!isDate(date) || !isTime(start_time) || (end_time && !isTime(end_time))) return;

  const { startsAt, endsAt } = activityTimes(date, start_time, end_time);
  const now = new Date();
  if (startsAt <= now) {
    ctx.addIssue({ code: 'custom', path: ['start_time'], message: 'Pick a time in the future.' });
  } else if (startsAt > latestStart(now)) {
    ctx.addIssue({
      code: 'custom',
      path: ['date'],
      message: `Pick a date in the next ${ACTIVITY.monthsAhead} months.`,
    });
  }
  if (endsAt && endsAt <= startsAt) {
    ctx.addIssue({ code: 'custom', path: ['end_time'], message: 'End after the start time.' });
  }
}

/** The date and times as the instants the database functions take. */
function toInstants<T extends Times>({ date, start_time, end_time, ...activity }: T) {
  const { startsAt, endsAt } = activityTimes(date, start_time, end_time);
  return { ...activity, starts_at: startsAt.toISOString(), ends_at: endsAt?.toISOString() };
}

/** The create form's fields. The output is create_activity()'s arguments. */
export const newActivity = z
  .object({
    idempotency_key: z.uuid(),
    title: z
      .string({ error: 'Add a title.' })
      .trim()
      .min(ACTIVITY.title.min, `Use at least ${ACTIVITY.title.min} characters.`)
      .max(ACTIVITY.title.max, `Use ${ACTIVITY.title.max} characters or fewer.`),
    date: z.iso.date({ error: 'Choose a date.' }),
    start_time: z.iso.time({ error: 'Choose a start time.' }),
    location_name: z
      .string({ error: 'Add a place.' })
      .trim()
      .min(1, 'Add a place.')
      .max(ACTIVITY.place.max, `Use ${ACTIVITY.place.max} characters or fewer.`),
    category_id: z.string({ error: 'Choose a category.' }),
    description: z
      .string()
      .trim()
      .max(ACTIVITY.description.max, `Use ${ACTIVITY.description.max} characters or fewer.`)
      .optional(),
    end_time: z.iso.time({ error: 'Choose an end time, or leave it empty.' }).optional(),
    cost_note: z
      .string()
      .trim()
      .max(ACTIVITY.costNote.max, `Use ${ACTIVITY.costNote.max} characters or fewer.`)
      .optional(),
  })
  .superRefine(checkTimes)
  .transform(toInstants);

/** The edit form's fields. The output is update_activity()'s patch, the id and the version shown. */
export const activityChanges = z
  .object(newActivity.in.shape)
  .omit({ idempotency_key: true })
  .extend({ id: z.uuid(), version: z.number().int() })
  .superRefine(checkTimes)
  .transform(toInstants);

/** The edit form's fields once an activity has started: only the description (FR-ACT-4). */
export const descriptionChange = z.object({
  id: z.uuid(),
  version: z.number().int(),
  description: newActivity.in.shape.description,
});

/** Cancelling an activity (ACT-05), with an optional reason for its banner. */
export const cancellation = z.object({
  id: z.uuid(),
  reason: z
    .string()
    .trim()
    .max(
      ACTIVITY.cancelReason.max,
      `Use ${ACTIVITY.cancelReason.max} characters or fewer for the reason.`
    )
    .optional(),
});

/** Restoring a cancelled activity (ACT-05). */
export const restoration = z.object({ id: z.uuid() });
