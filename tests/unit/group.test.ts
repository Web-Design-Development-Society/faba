import { describe, expect, it } from 'vitest';
import { groupRole, groupTransfer, newGroup } from '../../src/lib/validation/group';

const valid = {
  idempotency_key: 'a0000000-0000-4000-8000-000000000001',
  name: 'Trail Runners',
  category_id: 'outdoors',
};

describe('newGroup', () => {
  it('trims, and is open by default', () => {
    expect(
      newGroup.parse({ ...valid, name: '  Trail Runners ', description: ' Saturdays ' })
    ).toEqual({
      ...valid,
      description: 'Saturdays',
      join_policy: 'open',
    });
  });

  it.each([
    [{ name: 'Hi' }, 'name', 'Use at least 3 characters.'],
    [{ name: 'x'.repeat(61) }, 'name', 'Use 60 characters or fewer.'],
    [{ description: 'x'.repeat(1001) }, 'description', 'Use 1000 characters or fewer.'],
    [{ join_policy: 'invite' }, 'join_policy', 'Choose who can join.'],
  ])('refuses %j', (input, field, message) => {
    const result = newGroup.safeParse({ ...valid, ...input });
    expect(result.success).toBe(false);
    expect(result.error?.issues).toEqual([expect.objectContaining({ path: [field], message })]);
  });
});

const ids = {
  group_id: 'b0000000-0000-4000-8000-000000000001',
  user_id: 'c0000000-0000-4000-8000-000000000001',
};

describe('groupRole', () => {
  it('makes organizers and members, and nothing else', () => {
    expect(groupRole.parse({ ...ids, role: 'organizer' })).toEqual({ ...ids, role: 'organizer' });
    expect(groupRole.safeParse({ ...ids, role: 'owner' }).error?.issues[0].message).toBe(
      'Choose a role.'
    );
  });
});

describe('groupTransfer', () => {
  it('needs the new owner', () => {
    expect(groupTransfer.safeParse({ group_id: ids.group_id }).error?.issues[0]).toEqual(
      expect.objectContaining({ path: ['user_id'], message: 'Pick the new owner.' })
    );
  });

  it("trims the reason, and leaves out an empty one, for the owner's", () => {
    expect(groupTransfer.parse({ ...ids, reason: '  Owner asked ' })).toEqual({
      ...ids,
      reason: 'Owner asked',
    });
    expect(groupTransfer.parse({ ...ids, reason: '  ' })).toEqual({ ...ids, reason: undefined });
  });
});
