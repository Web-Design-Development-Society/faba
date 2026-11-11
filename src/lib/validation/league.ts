// Leagues and seasons (LEAG-01). A league is a group, so its name and category follow the group
// rules, and create_league() checks them again. A season's dates, format and points match the
// league_seasons table's CHECK constraints, and create_season() checks the rest.
import { z } from 'astro/zod';

const name = z
  .string({ error: 'Give the league a name.' })
  .trim()
  .min(3, 'Use 3 to 60 characters for the name.')
  .max(60, 'Use 3 to 60 characters for the name.');

/** Starting a league, which is a group marked as one. */
export const newLeague = z.object({
  name,
  category_id: z.string().min(1, 'Choose a category.').max(40),
  description: z
    .string()
    .trim()
    .max(1000, 'Use 1000 characters or fewer for the description.')
    .optional(),
  join_policy: z.enum(['open', 'approval'], { error: 'Choose how people join.' }),
});

const day = z.iso.date({ error: 'Pick a date.' });

/** Signing up for a season (LEAG-02). A form leaves an empty note out as null, so it's nullish. */
export const newRegistration = z.object({
  season_id: z.uuid({ error: 'Pick a season.' }),
  kind: z.enum(['player', 'free_agent'], { error: 'Sign up as a player or a free agent.' }),
  note: z
    .string()
    .trim()
    .max(280, 'Use 280 characters or fewer for the note.')
    .nullish()
    .transform((note) => note || undefined),
});

/** Withdrawing from a season (LEAG-02). */
export const withdrawal = z.object({ season_id: z.uuid({ error: 'Pick a season.' }) });

const teamName = z
  .string({ error: 'Name the team.' })
  .trim()
  .min(1, 'Name the team.')
  .max(40, 'Use 40 characters or fewer for the name.');

// A colour from a colour input, as #rrggbb.
const colour = z.string({ error: 'Pick a colour.' }).regex(/^#[0-9a-fA-F]{6}$/, 'Pick a colour.');

// A form leaves "no captain" or "no team" blank, which counts as none.
const optionalId = z
  .union([z.literal(''), z.uuid()])
  .nullish()
  .transform((id) => id || null);

/** Making a team in a season (LEAG-03). */
export const newTeam = z.object({
  season_id: z.uuid({ error: 'Pick a season.' }),
  name: teamName,
  color: colour,
});

/** Renaming a team, changing its colour, or naming its captain (LEAG-03). */
export const teamEdit = z.object({
  team_id: z.uuid({ error: 'Pick a team.' }),
  name: teamName,
  color: colour,
  captain_id: optionalId,
});

/** Putting a player on a team, moving them, or taking them off (LEAG-03). */
export const assignment = z.object({
  season_id: z.uuid({ error: 'Pick a season.' }),
  user_id: z.uuid({ error: 'Pick a player.' }),
  team_id: optionalId,
});

// A time from a time input, as HH:MM, in Boise time.
const clock = z.string({ error: 'Pick a time.' }).regex(/^\d{2}:\d{2}$/, 'Pick a time.');

const place = z
  .string({ error: 'Give the place.' })
  .trim()
  .min(1, 'Give the place.')
  .max(120, 'Use 120 characters or fewer for the place.');

/** Making a season's round robin (LEAG-04). The weekday is 1 for Monday to 7 for Sunday. */
export const newSchedule = z.object({
  season_id: z.uuid({ error: 'Pick a season.' }),
  first_day: day,
  weekday: z.coerce
    .number({ error: 'Pick a day of the week.' })
    .int()
    .min(1, 'Pick a day of the week.')
    .max(7, 'Pick a day of the week.'),
  starts_time: clock,
  place,
});

/** Changing one game's day, time or place (LEAG-04). */
export const gameEdit = z.object({
  game_id: z.uuid({ error: 'Pick a game.' }),
  day,
  starts_time: clock,
  place,
});

// A score from a number input: a whole number from 0 to 999. A blank one is an error, not a 0.
const score = z
  .string({ error: 'Enter both scores.' })
  .regex(/^\d{1,3}$/, 'Scores are whole numbers from 0 to 999.')
  .transform(Number);

/** A captain reporting a game's score (LEAG-05). Home and away are the game's two teams. */
export const scoreReport = z.object({
  game_id: z.uuid({ error: 'Pick a game.' }),
  home_score: score,
  away_score: score,
});

/** A game's score, confirmed by the other captain or an organizer (LEAG-05). */
export const scoreConfirmation = z.object({ game_id: z.uuid({ error: 'Pick a game.' }) });

/** An organizer setting a score, with the reason for the audit log (LEAG-05). */
export const scoreOverride = scoreReport.extend({
  reason: z
    .string({ error: 'Give a reason. It goes to the audit log.' })
    .trim()
    .min(1, 'Give a reason. It goes to the audit log.')
    .max(500, 'Use 500 characters or fewer for the reason.'),
});

/** An organizer recording that a team forfeited a game (LEAG-05). */
export const forfeit = z.object({
  game_id: z.uuid({ error: 'Pick a game.' }),
  forfeit_team_id: z.uuid({ error: 'Pick the team that forfeited.' }),
});

/** A captain asks the free agents for a sub for a game (LEAG-06). */
export const subRequest = z.object({ game_id: z.uuid({ error: 'Pick a game.' }) });

/** A free agent takes a sub spot (LEAG-06). */
export const subAcceptance = z.object({ request_id: z.uuid({ error: 'Pick a sub request.' }) });

/** A player's answer for a game: "yes" or "no", from two buttons (LEAG-07). */
export const availability = z.object({
  game_id: z.uuid({ error: 'Pick a game.' }),
  can_play: z
    .enum(['yes', 'no'], { error: 'Say whether you can play.' })
    .transform((v) => v === 'yes'),
});

/** Entering a ladder's players, so each one is a team of one (LEAG-08). */
export const ladderEntry = z.object({ season_id: z.uuid({ error: 'Pick a season.' }) });

// A date from a date input, as YYYY-MM-DD.
/** A season in a league. The team sizes and points default to the usual 3, 1 and 0. */
export const newSeason = z
  .object({
    group_id: z.uuid(),
    name: z
      .string({ error: 'Name the season.' })
      .trim()
      .min(3, 'Use 3 to 60 characters for the name.')
      .max(60, 'Use 3 to 60 characters for the name.'),
    starts_on: day,
    ends_on: day,
    format: z.enum(['teams', 'ladder'], { error: 'Choose a format.' }),
    team_min: z.coerce.number().int().min(1).max(20),
    team_max: z.coerce.number().int().min(1).max(20),
    points_win: z.coerce.number().int().min(0).max(10),
    points_tie: z.coerce.number().int().min(0).max(10),
    points_loss: z.coerce.number().int().min(0).max(10),
    registration_open: z.boolean(),
    active: z.boolean(),
  })
  .refine((season) => season.ends_on >= season.starts_on, {
    path: ['ends_on'],
    message: 'The season ends on or after its first day.',
  })
  .refine((season) => season.team_min <= season.team_max, {
    path: ['team_max'],
    message: 'The largest team is at least the smallest.',
  })
  .refine(
    (season) => season.format !== 'ladder' || (season.team_min === 1 && season.team_max === 1),
    {
      path: ['team_max'],
      message: 'A ladder is for one person at a time, so its team size is 1.',
    }
  );
