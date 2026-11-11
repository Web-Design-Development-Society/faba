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

// A date from a date input, as YYYY-MM-DD.
const day = z.iso.date({ error: 'Pick a date.' });

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
