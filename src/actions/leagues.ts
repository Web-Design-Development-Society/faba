// League Actions (LEAG-01). Each checks who's signed in, and Postgres checks the league, who runs it,
// and every rule again (ADR-004).
import { ActionError, defineAction } from 'astro:actions';
import { actionErrorFor } from '../lib/server/errors';
import {
  assignment,
  availability,
  ladderEntry,
  forfeit,
  gameEdit,
  newLeague,
  newSchedule,
  newRegistration,
  newSeason,
  newTeam,
  scoreConfirmation,
  scoreOverride,
  scoreReport,
  subAcceptance,
  subRequest,
  teamEdit,
  withdrawal,
} from '../lib/validation/league';

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

  /** Signing up for a season as a player or a free agent (LEAG-02). */
  register: defineAction({
    accept: 'form',
    input: newRegistration,
    handler: async ({ season_id, kind, note }, { locals }) => {
      if (!locals.user) throw new ActionError({ code: 'UNAUTHORIZED' });

      const { error } = await locals.supabase.rpc('join_season', { season_id, kind, note });
      if (error) throw new ActionError(actionErrorFor(error));
      return { season_id };
    },
  }),

  /** Withdrawing from a season, until its teams are set (LEAG-02). */
  withdraw: defineAction({
    accept: 'form',
    input: withdrawal,
    handler: async ({ season_id }, { locals }) => {
      if (!locals.user) throw new ActionError({ code: 'UNAUTHORIZED' });

      const { error } = await locals.supabase.rpc('withdraw_from_season', { season_id });
      if (error) throw new ActionError(actionErrorFor(error));
      return { season_id };
    },
  }),

  /** Making a team in a season (LEAG-03). */
  createTeam: defineAction({
    accept: 'form',
    input: newTeam,
    handler: async ({ season_id, name, color }, { locals }) => {
      if (!locals.user) throw new ActionError({ code: 'UNAUTHORIZED' });

      const { data, error } = await locals.supabase.rpc('create_team', { season_id, name, color });
      if (error) throw new ActionError(actionErrorFor(error));
      return { team_id: data };
    },
  }),

  /** Renaming a team, changing its colour, or naming its captain (LEAG-03). */
  updateTeam: defineAction({
    accept: 'form',
    input: teamEdit,
    handler: async ({ team_id, name, color, captain_id }, { locals }) => {
      if (!locals.user) throw new ActionError({ code: 'UNAUTHORIZED' });

      const { error } = await locals.supabase.rpc('update_team', {
        team_id,
        name,
        color,
        captain_id: captain_id ?? undefined,
      });
      if (error) throw new ActionError(actionErrorFor(error));
      return { team_id };
    },
  }),

  /** Putting a player on a team, moving them, or taking them off (LEAG-03). */
  assignPlayer: defineAction({
    accept: 'form',
    input: assignment,
    handler: async ({ season_id, user_id, team_id }, { locals }) => {
      if (!locals.user) throw new ActionError({ code: 'UNAUTHORIZED' });

      const { error } = await locals.supabase.rpc('assign_player', {
        season_id,
        user_id,
        team_id: team_id ?? undefined,
      });
      if (error) throw new ActionError(actionErrorFor(error));
      return { user_id };
    },
  }),

  /** Making a season's round robin, one game a week for each pair of teams (LEAG-04). */
  generateSchedule: defineAction({
    accept: 'form',
    input: newSchedule,
    handler: async ({ season_id, first_day, weekday, starts_time, place }, { locals }) => {
      if (!locals.user) throw new ActionError({ code: 'UNAUTHORIZED' });

      const { data, error } = await locals.supabase.rpc('schedule_round_robin', {
        season_id,
        first_day,
        weekday,
        starts_time,
        place,
      });
      if (error) throw new ActionError(actionErrorFor(error));
      return { games: data };
    },
  }),

  /** Changing one game's day, time or place (LEAG-04). */
  editGame: defineAction({
    accept: 'form',
    input: gameEdit,
    handler: async ({ game_id, day, starts_time, place }, { locals }) => {
      if (!locals.user) throw new ActionError({ code: 'UNAUTHORIZED' });

      const { error } = await locals.supabase.rpc('update_game', {
        game_id,
        day,
        starts_time,
        place,
      });
      if (error) throw new ActionError(actionErrorFor(error));
      return { game_id };
    },
  }),

  /** A captain reports a game's score, which the other captain or an organizer confirms (LEAG-05). */
  reportScore: defineAction({
    accept: 'form',
    input: scoreReport,
    handler: async ({ game_id, home_score, away_score }, { locals }) => {
      if (!locals.user) throw new ActionError({ code: 'UNAUTHORIZED' });

      const { error } = await locals.supabase.rpc('report_score', {
        game_id,
        home_score,
        away_score,
      });
      if (error) throw new ActionError(actionErrorFor(error));
      return { game_id };
    },
  }),

  /** The other captain, or an organizer, confirms a reported score (LEAG-05). */
  confirmScore: defineAction({
    accept: 'form',
    input: scoreConfirmation,
    handler: async ({ game_id }, { locals }) => {
      if (!locals.user) throw new ActionError({ code: 'UNAUTHORIZED' });

      const { error } = await locals.supabase.rpc('confirm_score', { game_id });
      if (error) throw new ActionError(actionErrorFor(error));
      return { game_id };
    },
  }),

  /** An organizer sets a score, with the reason for the audit log (LEAG-05). */
  overrideScore: defineAction({
    accept: 'form',
    input: scoreOverride,
    handler: async ({ game_id, home_score, away_score, reason }, { locals }) => {
      if (!locals.user) throw new ActionError({ code: 'UNAUTHORIZED' });

      const { error } = await locals.supabase.rpc('override_score', {
        game_id,
        home_score,
        away_score,
        reason,
      });
      if (error) throw new ActionError(actionErrorFor(error));
      return { game_id };
    },
  }),

  /** An organizer records that a team forfeited a game (LEAG-05). */
  forfeitGame: defineAction({
    accept: 'form',
    input: forfeit,
    handler: async ({ game_id, forfeit_team_id }, { locals }) => {
      if (!locals.user) throw new ActionError({ code: 'UNAUTHORIZED' });

      const { error } = await locals.supabase.rpc('forfeit_game', {
        game_id,
        forfeit_team_id,
      });
      if (error) throw new ActionError(actionErrorFor(error));
      return { game_id };
    },
  }),

  /** A captain asks the season's free agents for a sub for a game (LEAG-06). */
  requestSub: defineAction({
    accept: 'form',
    input: subRequest,
    handler: async ({ game_id }, { locals }) => {
      if (!locals.user) throw new ActionError({ code: 'UNAUTHORIZED' });

      const { data, error } = await locals.supabase.rpc('request_sub', { game_id });
      if (error) throw new ActionError(actionErrorFor(error));
      return { request_id: data };
    },
  }),

  /** A free agent takes a sub spot, which is that game only (LEAG-06). */
  acceptSub: defineAction({
    accept: 'form',
    input: subAcceptance,
    handler: async ({ request_id }, { locals }) => {
      if (!locals.user) throw new ActionError({ code: 'UNAUTHORIZED' });

      const { error } = await locals.supabase.rpc('accept_sub', { request_id });
      if (error) throw new ActionError(actionErrorFor(error));
      return { request_id };
    },
  }),

  /** A player says whether they can play a game, which is also their RSVP (LEAG-07). */
  setAvailability: defineAction({
    accept: 'form',
    input: availability,
    handler: async ({ game_id, can_play }, { locals }) => {
      if (!locals.user) throw new ActionError({ code: 'UNAUTHORIZED' });

      const { error } = await locals.supabase.rpc('set_game_availability', { game_id, can_play });
      if (error) throw new ActionError(actionErrorFor(error));
      return { game_id };
    },
  }),

  /** Entering a ladder's players, so each is a team of one (LEAG-08). */
  enterLadder: defineAction({
    accept: 'form',
    input: ladderEntry,
    handler: async ({ season_id }, { locals }) => {
      if (!locals.user) throw new ActionError({ code: 'UNAUTHORIZED' });

      const { data, error } = await locals.supabase.rpc('enter_ladder', { season_id });
      if (error) throw new ActionError(actionErrorFor(error));
      return { players: data };
    },
  }),
};
