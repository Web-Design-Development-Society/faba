// What the database's error keys mean for an Action: its error code and a plain sentence (design
// document section 9.9). The keys come from the RPC functions in supabase/migrations.
import type { ActionErrorCode } from 'astro:actions';

const KNOWN: Record<string, { code: ActionErrorCode; message: string }> = {
  QUOTA_EXCEEDED: {
    code: 'TOO_MANY_REQUESTS',
    message: 'You can post up to 10 activities a day. Try again tomorrow.',
  },
  START_IN_PAST: { code: 'BAD_REQUEST', message: 'Pick a start time in the future.' },
  START_TOO_FAR: { code: 'BAD_REQUEST', message: 'Pick a date in the next 12 months.' },
  END_BEFORE_START: { code: 'BAD_REQUEST', message: 'End after the start time.' },
  INVALID_CATEGORY: { code: 'BAD_REQUEST', message: 'Choose one of the categories.' },
  NOT_ACTIVE: { code: 'FORBIDDEN', message: "Your account can't do that right now." },
  ACTIVITY_NOT_FOUND: {
    code: 'NOT_FOUND',
    message: "This activity isn't available. It may have been removed.",
  },
  ACTIVITY_CANCELLED: {
    code: 'CONFLICT',
    message: "This activity is cancelled, so it isn't taking RSVPs.",
  },
  ACTIVITY_OVER: { code: 'CONFLICT', message: "This activity is over, so it isn't taking RSVPs." },
  ORGANIZER_GOING: { code: 'BAD_REQUEST', message: "You're hosting, so you're already going." },
  NOT_ORGANIZER: { code: 'FORBIDDEN', message: 'Only the organizer can edit this activity.' },
  STALE_EDIT: {
    code: 'CONFLICT',
    message: 'This activity changed after you opened it. Open Edit again to see the changes.',
  },
  ACTIVITY_STARTED: {
    code: 'CONFLICT',
    message: 'This activity has started, so only its description can change.',
  },
};

/**
 * The Action error for a database error. Unknown errors get a short reference, which is logged
 * with the details so a member's report can be matched to them.
 */
export function actionErrorFor(error: { message: string; code?: string }): {
  code: ActionErrorCode;
  message: string;
} {
  const known = KNOWN[error.message];
  if (known) return known;

  const reference = crypto.randomUUID().slice(0, 8);
  console.error(JSON.stringify({ reference, code: error.code, message: error.message }));
  return {
    code: 'INTERNAL_SERVER_ERROR',
    message: `Something went wrong. Please try again. (Reference ${reference})`,
  };
}
