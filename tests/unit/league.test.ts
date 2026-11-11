// League validation (LEAG-01, LEAG-02). A form leaves an empty note out as null, so it must pass.
import { describe as group, expect, it } from 'vitest';
import {
  assignment,
  gameEdit,
  newRegistration,
  newSchedule,
  newTeam,
  teamEdit,
  withdrawal,
} from '../../src/lib/validation/league';

const seasonId = '3f6c2d4e-1a2b-4c3d-8e9f-0a1b2c3d4e5f';

group('newRegistration', () => {
  it('takes a player or a free agent, with an optional note', () => {
    expect(
      newRegistration.parse({ season_id: seasonId, kind: 'player', note: '  Keen  ' })
    ).toEqual({ season_id: seasonId, kind: 'player', note: 'Keen' });
    expect(newRegistration.parse({ season_id: seasonId, kind: 'free_agent', note: null })).toEqual({
      season_id: seasonId,
      kind: 'free_agent',
      note: undefined,
    });
    expect(newRegistration.parse({ season_id: seasonId, kind: 'free_agent' }).note).toBeUndefined();
  });

  it('rejects another kind and a note over 280 characters', () => {
    expect(newRegistration.safeParse({ season_id: seasonId, kind: 'spectator' }).success).toBe(
      false
    );
    expect(
      newRegistration.safeParse({ season_id: seasonId, kind: 'player', note: 'x'.repeat(281) })
        .success
    ).toBe(false);
  });
});

group('withdrawal', () => {
  it('needs a season', () => {
    expect(withdrawal.safeParse({ season_id: seasonId }).success).toBe(true);
    expect(withdrawal.safeParse({ season_id: 'nope' }).success).toBe(false);
  });
});

group('teams', () => {
  it('needs a name of up to 40 characters and a hex colour', () => {
    expect(
      newTeam.safeParse({ season_id: seasonId, name: '  Reds ', color: '#ff0000' }).data?.name
    ).toBe('Reds');
    expect(newTeam.safeParse({ season_id: seasonId, name: '  ', color: '#ff0000' }).success).toBe(
      false
    );
    expect(newTeam.safeParse({ season_id: seasonId, name: 'Reds', color: 'red' }).success).toBe(
      false
    );
  });

  it('reads a blank captain or team as none', () => {
    const teamId = '3f6c2d4e-1a2b-4c3d-8e9f-0a1b2c3d4e5f';
    expect(
      teamEdit.parse({ team_id: teamId, name: 'Reds', color: '#ff0000', captain_id: '' }).captain_id
    ).toBeNull();
    expect(
      assignment.parse({ season_id: seasonId, user_id: teamId, team_id: '' }).team_id
    ).toBeNull();
  });
});

group('schedule', () => {
  it('takes a first day, a weekday from 1 to 7, a time and a place', () => {
    const schedule = {
      season_id: seasonId,
      first_day: '2027-03-01',
      weekday: '2',
      starts_time: '18:00',
      place: ' Gym A ',
    };
    expect(newSchedule.parse(schedule)).toEqual({
      season_id: seasonId,
      first_day: '2027-03-01',
      weekday: 2,
      starts_time: '18:00',
      place: 'Gym A',
    });
    expect(newSchedule.safeParse({ ...schedule, weekday: '8' }).success).toBe(false);
    expect(newSchedule.safeParse({ ...schedule, starts_time: '6pm' }).success).toBe(false);
    expect(newSchedule.safeParse({ ...schedule, place: '  ' }).success).toBe(false);
  });

  it('changes a game with a day, a time and a place', () => {
    expect(
      gameEdit.safeParse({
        game_id: seasonId,
        day: '2027-03-08',
        starts_time: '19:30',
        place: 'Field 2',
      }).success
    ).toBe(true);
    expect(
      gameEdit.safeParse({ game_id: seasonId, day: 'March', starts_time: '19:30', place: 'x' })
        .success
    ).toBe(false);
  });
});
