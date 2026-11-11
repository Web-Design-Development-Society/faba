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
  NOT_LEAGUE_ORGANIZER: {
    code: 'FORBIDDEN',
    message: 'Only the league organizers can start a season.',
  },
  NOT_A_LEAGUE: {
    code: 'BAD_REQUEST',
    message: "This group isn't a league, so it has no seasons.",
  },
  SEASON_NOT_FOUND: {
    code: 'NOT_FOUND',
    message: "This season isn't available. It may have been removed.",
  },
  REGISTRATION_CLOSED: {
    code: 'CONFLICT',
    message: "This season isn't taking sign-ups right now.",
  },
  INVALID_REGISTRATION: {
    code: 'BAD_REQUEST',
    message: 'Sign up as a player or a free agent.',
  },
  TEAMS_SET: {
    code: 'CONFLICT',
    message: 'The teams are set, so ask an organizer to change your sign-up.',
  },
  INVALID_TEAM: {
    code: 'BAD_REQUEST',
    message: 'Use a name of up to 40 characters and a colour.',
  },
  TEAM_NAME_TAKEN: { code: 'CONFLICT', message: 'A team in this season already has that name.' },
  TEAM_NOT_FOUND: { code: 'NOT_FOUND', message: "This team isn't available." },
  NOT_A_PLAYER: {
    code: 'BAD_REQUEST',
    message: "Only players can be on a team. Free agents aren't put on teams.",
  },
  REGISTRATION_NOT_FOUND: {
    code: 'NOT_FOUND',
    message: "This player hasn't signed up for the season.",
  },
  CAPTAIN_NOT_ON_TEAM: {
    code: 'BAD_REQUEST',
    message: 'The captain has to be a player on the team. Put them on it first.',
  },
  SEASON_ALREADY_ACTIVE: {
    code: 'BAD_REQUEST',
    message: 'This league already has an active season. End it before starting another.',
  },
  ACTIVITY_NOT_FOUND: {
    code: 'NOT_FOUND',
    message: "This activity isn't available. It may have been removed.",
  },
  ACTIVITY_CANCELLED: {
    code: 'CONFLICT',
    message: "This activity is cancelled, so it isn't taking RSVPs.",
  },
  ACTIVITY_OVER: { code: 'CONFLICT', message: "This activity is over, so it isn't taking RSVPs." },
  ACTIVITY_FULL: { code: 'CONFLICT', message: 'This activity is full. Every spot is taken.' },
  INVALID_CAPACITY: { code: 'BAD_REQUEST', message: 'Allow between 1 and 500 spots.' },
  TOO_MANY_TAGS: { code: 'BAD_REQUEST', message: 'Pick up to 3 tags.' },
  INVALID_GUESTS: {
    code: 'BAD_REQUEST',
    message: "That's more guests than the organizer allows. Bring fewer.",
  },
  INVALID_TAG: {
    code: 'BAD_REQUEST',
    message: 'One of those tags is no longer offered. Pick another.',
  },
  ORGANIZER_GOING: { code: 'BAD_REQUEST', message: "You're hosting, so you're already going." },
  NOT_ORGANIZER: { code: 'FORBIDDEN', message: 'Only the organizer can edit this activity.' },
  NOT_ATTENDEE_MANAGER: {
    code: 'FORBIDDEN',
    message: 'Only the organizer, a co-organizer, a group organizer or a moderator can do that.',
  },
  CANNOT_REMOVE_ORGANIZER: {
    code: 'BAD_REQUEST',
    message: "The organizer is always going, so they can't be taken off the list.",
  },
  TOO_MANY_CO_ORGANIZERS: {
    code: 'BAD_REQUEST',
    message: 'An activity can have up to 3 co-organizers. Remove one to add another.',
  },
  STALE_EDIT: {
    code: 'CONFLICT',
    message: 'This activity changed after you opened it. Open Edit again to see the changes.',
  },
  ACTIVITY_STARTED: {
    code: 'CONFLICT',
    message:
      'This activity has started, so only its description and details for attendees can change.',
  },
  INVALID_PRIVATE_DETAILS: {
    code: 'BAD_REQUEST',
    message: 'Use 500 characters or fewer for the details for attendees.',
  },
  RESTORE_TOO_LATE: {
    code: 'CONFLICT',
    message: "This activity has started, so it can't be restored.",
  },
  REPORT_TARGET_NOT_FOUND: {
    code: 'NOT_FOUND',
    message: "This isn't available to report. It may have been removed.",
  },
  REPORT_OWN: { code: 'BAD_REQUEST', message: "You can't report something you posted." },
  ALREADY_REPORTED: {
    code: 'CONFLICT',
    message: "You've already reported this. A moderator will review it.",
  },
  NOT_MODERATOR: { code: 'FORBIDDEN', message: 'Only moderators can do that.' },
  REASON_REQUIRED: { code: 'BAD_REQUEST', message: 'Give a reason. It goes to the audit log.' },
  REPORT_NOT_OPEN: { code: 'CONFLICT', message: 'This report has already been handled.' },
  ALREADY_HIDDEN: { code: 'CONFLICT', message: 'This activity is already hidden.' },
  NOT_HIDDEN: { code: 'CONFLICT', message: "This activity isn't hidden." },
  MEMBER_NOT_FOUND: { code: 'NOT_FOUND', message: "This member isn't available." },
  SUSPEND_SELF: { code: 'BAD_REQUEST', message: "You can't suspend yourself." },
  SUSPEND_MODERATOR: {
    code: 'FORBIDDEN',
    message: 'Only admins can suspend a moderator or an admin.',
  },
  ALREADY_SUSPENDED: { code: 'CONFLICT', message: 'This member is already suspended.' },
  NOT_SUSPENDED: { code: 'CONFLICT', message: "This member isn't suspended." },
  ORGANIZER_ELIGIBLE: {
    code: 'CONFLICT',
    message: "This activity's organizer is still active, so it stays theirs.",
  },
  ACTIVITY_NOT_UPCOMING: {
    code: 'CONFLICT',
    message: 'This activity is cancelled or has started, so it stays as it is.',
  },
  NEW_HOST_NOT_GOING: { code: 'BAD_REQUEST', message: "Pick someone who's going." },
  ACCOUNT_NOT_FOUND: { code: 'NOT_FOUND', message: 'Your account is already deleted.' },
  REPORT_QUOTA_EXCEEDED: {
    code: 'TOO_MANY_REQUESTS',
    message: 'You can send up to 10 reports a day. Try again tomorrow.',
  },
  UPDATE_QUOTA_EXCEEDED: {
    code: 'TOO_MANY_REQUESTS',
    message: 'You can post up to 5 updates a day to an activity. Try again tomorrow.',
  },
  INVALID_BODY: { code: 'BAD_REQUEST', message: 'Write an update of up to 500 characters.' },
  UPDATE_NOT_FOUND: { code: 'NOT_FOUND', message: "This update isn't available." },
  UPDATE_ALREADY_HIDDEN: { code: 'CONFLICT', message: 'This update is already hidden.' },
  UPDATE_NOT_HIDDEN: { code: 'CONFLICT', message: "This update isn't hidden." },
  INVALID_GROUP_NAME: { code: 'BAD_REQUEST', message: 'Use 3 to 60 characters for the name.' },
  INVALID_GROUP_DESCRIPTION: {
    code: 'BAD_REQUEST',
    message: 'Use 1,000 characters or fewer for the description.',
  },
  INVALID_JOIN_POLICY: { code: 'BAD_REQUEST', message: 'Choose who can join.' },
  INVALID_VISIBILITY: {
    code: 'BAD_REQUEST',
    message: 'Choose a group, or make it for everyone.',
  },
  NOT_GROUP_ORGANIZER: {
    code: 'FORBIDDEN',
    message: "You can post under a group only when you're one of its organizers.",
  },
  GROUP_UPDATE_QUOTA_EXCEEDED: {
    code: 'TOO_MANY_REQUESTS',
    message: 'A group can have 3 updates a day. Try again tomorrow.',
  },
  GROUP_NOT_FOUND: {
    code: 'NOT_FOUND',
    message: "This group isn't available. It may have been removed.",
  },
  GROUP_ARCHIVED: {
    code: 'CONFLICT',
    message: "This group is archived, so it isn't taking members.",
  },
  OWNER_CANNOT_LEAVE: {
    code: 'CONFLICT',
    message: "You own this group, so you can't leave it yet. Hand it on to another member first.",
  },
  NOT_GROUP_OWNER: {
    code: 'FORBIDDEN',
    message: "Only the group's owner can do that.",
  },
  CANNOT_MANAGE_OWNER: {
    code: 'CONFLICT',
    message: "The group's owner stays its owner until they hand it on.",
  },
  INVALID_GROUP_ROLE: { code: 'BAD_REQUEST', message: 'Choose a role.' },
  GROUP_QUOTA_EXCEEDED: {
    code: 'TOO_MANY_REQUESTS',
    message: 'You can start up to 3 groups a month. Try again later.',
  },
  NOT_ADMIN: { code: 'FORBIDDEN', message: 'Only board admins can do that.' },
  NOT_BOARD_ACTIVITY: {
    code: 'BAD_REQUEST',
    message: 'Mark it as a board activity before announcing it.',
  },
  ALREADY_ANNOUNCED: { code: 'CONFLICT', message: 'This activity has already been announced.' },
  ANNOUNCE_TOO_LATE: {
    code: 'CONFLICT',
    message: "This activity has started, so it can't be announced.",
  },
  ANNOUNCE_UNAVAILABLE: {
    code: 'CONFLICT',
    message: "This activity is cancelled or hidden, so it can't be announced.",
  },
  ACTIVITY_HIDDEN: {
    code: 'CONFLICT',
    message: "This activity is hidden, so you can't post updates to it.",
  },
  NOT_ATTENDING: {
    code: 'BAD_REQUEST',
    message: "You can mute an activity once you're going or a maybe.",
  },
  INVALID_REPEATS: { code: 'BAD_REQUEST', message: 'Choose how often it repeats.' },
  UNTIL_BEFORE_START: {
    code: 'BAD_REQUEST',
    message: 'Pick a last date on or after the first.',
  },
  SERIES_TOO_LONG: {
    code: 'BAD_REQUEST',
    message: 'Pick a last date in the 12 months after the first.',
  },
  SERIES_NOT_FOUND: { code: 'NOT_FOUND', message: "This activity isn't part of a series." },
  NOT_IN_SERIES: {
    code: 'CONFLICT',
    message: 'This date changes on its own now. Choose Just this date.',
  },
  MONTHLY_DATE_FIXED: {
    code: 'BAD_REQUEST',
    message:
      'A monthly series stays on its day. Keep the date to change future dates, or choose Just this date.',
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
