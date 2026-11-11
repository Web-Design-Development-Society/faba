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
  .refine((season) => season.format === 'ladder' || season.team_min <= season.team_max, {
    path: ['team_max'],
    message: 'The largest team is at least the smallest.',
  });
// A ladder is for one person at a time, so the action sets its team sizes to 1, whatever the form
// held. The sizes don't matter to a ladder, so the form doesn't ask it to be exact.
