// Admin actions (MOD-08): categories, tags and roles. Each checks who's signed in, and Postgres
// checks they're an admin and every rule again (ADR-004). A role change needs a reason, which goes
// to the audit log.
import { ActionError, defineAction } from 'astro:actions';
import { z } from 'astro/zod';
import { actionErrorFor } from '../lib/server/errors';

const reason = z
  .string({ error: 'Give a reason. It goes to the audit log.' })
  .trim()
  .min(1, 'Give a reason. It goes to the audit log.')
  .max(500, 'Use 500 characters or fewer for the reason.');

export const admin = {
  /** Renames a category, or switches it on and off. */
  saveCategory: defineAction({
    accept: 'form',
    input: z.object({
      id: z.string().min(1).max(40),
      name: z.string().trim().min(1, 'Give the category a name.').max(40),
      is_active: z.boolean(),
    }),
    handler: async ({ id, name, is_active }, { locals }) => {
      if (!locals.user) throw new ActionError({ code: 'UNAUTHORIZED' });

      const { error } = await locals.supabase.rpc('admin_save_category', { id, name, is_active });
      if (error) throw new ActionError(actionErrorFor(error));
      return { id };
    },
  }),

  /** Adds a tag, or changes one: its name, whether it's offered, and its order. */
  saveTag: defineAction({
    accept: 'form',
    input: z.object({
      id: z
        .string()
        .trim()
        .regex(/^[a-z0-9-]{2,40}$/, 'Use 2 to 40 lowercase letters, numbers or dashes for the id.'),
      name: z.string().trim().min(1, 'Give the tag a name.').max(40),
      is_active: z.boolean(),
      sort_order: z.coerce.number().int().min(0).max(999),
    }),
    handler: async ({ id, name, is_active, sort_order }, { locals }) => {
      if (!locals.user) throw new ActionError({ code: 'UNAUTHORIZED' });

      const { error } = await locals.supabase.rpc('admin_save_tag', {
        id,
        name,
        is_active,
        sort_order,
      });
      if (error) throw new ActionError(actionErrorFor(error));
      return { id };
    },
  }),

  /** Makes a member a moderator or an admin, or takes the role away, with a reason. */
  setRole: defineAction({
    accept: 'form',
    input: z.object({
      user_id: z.uuid(),
      role: z.enum(['member', 'moderator', 'admin'], { error: 'Pick a role.' }),
      reason,
    }),
    handler: async ({ user_id, role, reason }, { locals }) => {
      if (!locals.user) throw new ActionError({ code: 'UNAUTHORIZED' });

      const { error } = await locals.supabase.rpc('admin_set_role', { user_id, role, reason });
      if (error) throw new ActionError(actionErrorFor(error));
      return { user_id, role };
    },
  }),
};
