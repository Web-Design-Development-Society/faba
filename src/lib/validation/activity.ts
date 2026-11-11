// Posting an activity (ACT-03), editing it with the same rules (ACT-04), and cancelling it
// (ACT-05). The limits match the activities table's CHECK constraints, and create_activity() and
// update_activity() check the time rules again.
import { z } from 'astro/zod';
import { REPEATS, type Repeats } from '../series';
import { rexburgInstant } from '../time';

export const ACTIVITY = {
  title: { min: 3, max: 80 },
  place: { max: 120 },
  description: { max: 2000 },
  costNote: { max: 60 },
  privateDetails: { max: 500 },
  cancelReason: { max: 200 },
  capacity: { min: 1, max: 500 },
  tags: { max: 3 },
  guests: { max: 5, suggested: 3 },
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

/** An activity for a group's members only needs its group (GRP-03). */
function checkGroup(
  { group_id, visibility }: { group_id?: string; visibility: string },
  ctx: z.RefinementCtx
) {
  if (visibility === 'group' && !group_id) {
    ctx.addIssue({
      code: 'custom',
      path: ['visibility'],
      message: 'Choose a group, or make it for everyone.',
    });
  }
}

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

/** `date` a year on, as `2027-11-07` for `2026-11-07`, the most a series can run (REC-01). */
function yearAfter(date: string): string {
  const later = new Date(`${date}T12:00:00Z`);
  later.setUTCFullYear(later.getUTCFullYear() + 1);
  return later.toISOString().slice(0, 10);
}

type Series = { date: string; repeats: string; until_date?: string };

/** A series' last date is on or after its first, and within 12 months of it (REC-01). */
function checkRepeats({ date, repeats, until_date }: Series, ctx: z.RefinementCtx) {
  if (repeats === 'none' || !until_date || !isDate(date) || !isDate(until_date)) return;

  if (until_date < date) {
    ctx.addIssue({
      code: 'custom',
      path: ['until_date'],
      message: 'Pick a last date on or after the first.',
    });
  } else if (until_date > yearAfter(date)) {
    ctx.addIssue({
      code: 'custom',
      path: ['until_date'],
      message: `Pick a last date in the ${ACTIVITY.monthsAhead} months after the first.`,
    });
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
    // RSVP-04. Empty means no limit.
    capacity: z
      .number({ error: 'Enter a number of spots, or leave it empty.' })
      .int('Enter a whole number of spots.')
      .min(ACTIVITY.capacity.min, `Allow at least ${ACTIVITY.capacity.min} spot.`)
      .max(ACTIVITY.capacity.max, `Allow ${ACTIVITY.capacity.max} spots or fewer.`)
      .optional(),
    // RSVP-06. Without Guests welcome, the most each can bring is kept for later.
    guests_allowed: z.boolean().optional(),
    max_guests_per_rsvp: z
      .number({ error: 'Choose how many guests each member can bring.' })
      .int()
      .min(1, 'Allow at least 1 guest each.')
      .max(ACTIVITY.guests.max, `Allow ${ACTIVITY.guests.max} guests each or fewer.`)
      .optional(),
    // ACT-09. Only the organizer, members going and moderators can read them.
    private_details: z
      .string()
      .trim()
      .max(ACTIVITY.privateDetails.max, `Use ${ACTIVITY.privateDetails.max} characters or fewer.`)
      .optional(),
    // SRCH-03. set_activity_tags() checks they're offered.
    tags: z
      .array(z.string())
      .max(ACTIVITY.tags.max, `Pick up to ${ACTIVITY.tags.max} tags.`)
      .optional(),
    // ACT-07. The activity it's a copy of, kept for analytics only.
    copied_from_id: z.uuid().optional(),
    // GRP-03. A group the member organizes, and who sees it. create_activity() checks the group.
    group_id: z.uuid().optional(),
    visibility: z
      .enum(['members', 'group'], { error: 'Choose who can see it.' })
      .default('members'),
    // REC-01. How often it repeats, and the last date it can fall on, or empty to roll on.
    repeats: z
      .enum(Object.keys(REPEATS) as Repeats[], { error: 'Choose how often it repeats.' })
      .default('none'),
    until_date: z.iso.date({ error: 'Choose a last date, or leave it empty.' }).optional(),
  })
  .superRefine(checkTimes)
  .superRefine(checkGroup)
  .superRefine(checkRepeats)
  .transform(toInstants);

/** The edit form's fields. The output is update_activity()'s patch, the id and the version shown. */
export const activityChanges = z
  .object(newActivity.in.shape)
  .omit({
    idempotency_key: true,
    copied_from_id: true,
    group_id: true,
    visibility: true,
    repeats: true,
    until_date: true,
  })
  .extend({ id: z.uuid(), version: z.number().int() })
  .superRefine(checkTimes)
  .transform(toInstants);

/**
 * The edit form's fields once an activity has started: only the description (FR-ACT-4), and the
 * details for attendees (ACT-09), such as a gate code that changed.
 */
export const descriptionChange = z.object({
  id: z.uuid(),
  version: z.number().int(),
  description: newActivity.in.shape.description,
  private_details: newActivity.in.shape.private_details,
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
