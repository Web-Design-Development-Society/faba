// League Actions (LEAG-01). Each checks who's signed in, and Postgres checks the league, who runs it,
// and every rule again (ADR-004).
import { ActionError, defineAction } from 'astro:actions';
import { actionErrorFor } from '../lib/server/errors';
import { newLeague, newSeason } from '../lib/validation/league';

export const leagues = {
  /** Starting a league, which returns its slug (LEAG-01). */
  create: defineAction({
    accept: 'form',
    input: newLeague,
    handler: async ({ name, category_id, description, join_policy }, { locals }) => {
      if (!locals.user) throw new ActionError({ code: 'UNAUTHORIZED' });

      const { data: slug, error } = await locals.supabase.rpc('create_league', {
        name,
        category_id,
        description,
        join_policy,
      });
      if (error) throw new ActionError(actionErrorFor(error));
      return { slug };
    },
  }),

  /** Starting a season in a league, which returns its id (LEAG-01). */
  createSeason: defineAction({
    accept: 'form',
    input: newSeason,
    handler: async (season, { locals }) => {
      if (!locals.user) throw new ActionError({ code: 'UNAUTHORIZED' });

      const { data, error } = await locals.supabase.rpc('create_season', {
        group_id: season.group_id,
        name: season.name,
        starts_on: season.starts_on,
        ends_on: season.ends_on,
        format: season.format,
        team_min: season.format === 'ladder' ? 1 : season.team_min,
        team_max: season.format === 'ladder' ? 1 : season.team_max,
        points_win: season.points_win,
        points_tie: season.points_tie,
        points_loss: season.points_loss,
        registration_open: season.registration_open,
        active: season.active,
      });
      if (error) throw new ActionError(actionErrorFor(error));
      return { season_id: data };
    },
  }),
};
