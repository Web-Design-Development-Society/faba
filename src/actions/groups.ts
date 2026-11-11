// Group Actions (GRP-01, GRP-02, GRP-04, GRP-05). Each checks who's signed in, and Postgres checks every rule again
// (ADR-004).
import { ActionError, defineAction } from 'astro:actions';
import { z } from 'astro/zod';
import { actionErrorFor } from '../lib/server/errors';
import { groupMember, groupRole, groupTransfer, newGroup } from '../lib/validation/group';
import { newGroupUpdate } from '../lib/validation/update';

export const groups = {
  /** Starting a group, as its owner (GRP-01). Returns its slug, for its address. */
  create: defineAction({
    accept: 'form',
    input: newGroup,
    handler: async (group, { locals }) => {
      if (!locals.user) throw new ActionError({ code: 'UNAUTHORIZED' });

      const { data: slug, error } = await locals.supabase.rpc('create_group', group);
      if (error) throw new ActionError(actionErrorFor(error));
      return { slug };
    },
  }),

  /**
   * Joining a group (GRP-02): at once for an open group, or a request to its organizers. Returns the
   * membership, `active` or `pending`.
   */
  join: defineAction({
    accept: 'form',
    input: z.object({ group_id: z.uuid() }),
    handler: async ({ group_id }, { locals }) => {
      if (!locals.user) throw new ActionError({ code: 'UNAUTHORIZED' });

      const { data: status, error } = await locals.supabase.rpc('join_group', { group_id });
      if (error) throw new ActionError(actionErrorFor(error));
      return { status: status as 'active' | 'pending' };
    },
  }),

  /**
   * Posting an update to a group's members (GRP-04). Posting again with the same idempotency key
   * returns the update already posted. Returns the group's id.
   */
  postUpdate: defineAction({
    accept: 'form',
    input: newGroupUpdate,
    handler: async ({ group_id, body, idempotency_key }, { locals }) => {
      if (!locals.user) throw new ActionError({ code: 'UNAUTHORIZED' });

      const { error } = await locals.supabase.rpc('post_group_update', {
        group_id,
        body,
        idempotency_key,
      });
      if (error) throw new ActionError(actionErrorFor(error));
      return { group_id };
    },
  }),

  /** Leaving a group, or withdrawing a request to join (GRP-02). Returns what they had. */
  leave: defineAction({
    accept: 'form',
    input: z.object({ group_id: z.uuid(), pending: z.boolean().optional() }),
    handler: async ({ group_id, pending }, { locals }) => {
      if (!locals.user) throw new ActionError({ code: 'UNAUTHORIZED' });

      const { error } = await locals.supabase.rpc('leave_group', { group_id });
      if (error) throw new ActionError(actionErrorFor(error));
      return { pending: !!pending };
    },
  }),

  /** Approving a request to join (GRP-05). The member hears they're in. */
  approve: defineAction({
    accept: 'form',
    input: groupMember,
    handler: async (member, { locals }) => {
      if (!locals.user) throw new ActionError({ code: 'UNAUTHORIZED' });

      const { error } = await locals.supabase.rpc('approve_group_member', member);
      if (error) throw new ActionError(actionErrorFor(error));
      return {};
    },
  }),

  /**
   * Removing a member, or declining a request to join, quietly (GRP-05). Returns whether it was a
   * request.
   */
  remove: defineAction({
    accept: 'form',
    input: groupMember.extend({ pending: z.boolean().optional() }),
    handler: async ({ group_id, user_id, pending }, { locals }) => {
      if (!locals.user) throw new ActionError({ code: 'UNAUTHORIZED' });

      const { error } = await locals.supabase.rpc('remove_group_member', { group_id, user_id });
      if (error) throw new ActionError(actionErrorFor(error));
      return { pending: !!pending };
    },
  }),

  /** Making a member an organizer, or a member again, which only the owner can (GRP-05). */
  setRole: defineAction({
    accept: 'form',
    input: groupRole,
    handler: async (change, { locals }) => {
      if (!locals.user) throw new ActionError({ code: 'UNAUTHORIZED' });

      const { error } = await locals.supabase.rpc('set_group_role', change);
      if (error) throw new ActionError(actionErrorFor(error));
      return { role: change.role };
    },
  }),

  /**
   * Handing a group on to one of its members, by its owner or a moderator (GRP-05). The new owner
   * hears it's theirs.
   */
  transfer: defineAction({
    accept: 'form',
    input: groupTransfer,
    handler: async (transfer, { locals }) => {
      if (!locals.user) throw new ActionError({ code: 'UNAUTHORIZED' });

      const { error } = await locals.supabase.rpc('transfer_group', transfer);
      if (error) throw new ActionError(actionErrorFor(error));
      return {};
    },
  }),
};
