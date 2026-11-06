// Limits for profile fields, shared by forms and Actions (design document section 9.9). They
// match the CHECK constraints on public.profiles.
import { z } from 'astro/zod';

export const DISPLAY_NAME = { min: 2, max: 50 };

export const PROFILE = {
  department: { max: 60 },
  bio: { max: 280 },
  interests: { max: 20 },
};

/** Faculty type (PROF-02): private, self-reported, and only used for anonymous totals. */
export const FACULTY_TYPES = {
  full_time: 'Full-time',
  part_time: 'Part-time',
  prefer_not: 'Prefer not to say',
};

export const displayName = z
  .string()
  .trim()
  .min(DISPLAY_NAME.min, 'Use at least 2 characters.')
  .max(DISPLAY_NAME.max, 'Use 50 characters or fewer.');

/** Editing the profile (PROF-02). A field left empty is undefined, which the Action clears. */
export const profileChanges = z.object({
  display_name: displayName,
  use_initials: z.boolean(),
  department: z
    .string()
    .trim()
    .max(PROFILE.department.max, `Use ${PROFILE.department.max} characters or fewer.`)
    .optional(),
  bio: z
    .string()
    .trim()
    .max(PROFILE.bio.max, `Use ${PROFILE.bio.max} characters or fewer.`)
    .optional(),
  interests: z.array(z.string()).max(PROFILE.interests.max),
  faculty_type: z.enum(['full_time', 'part_time', 'prefer_not']).optional(),
});

/** Deleting the account (PROF-05). Typing DELETE, exactly, confirms it. */
export const accountDeletion = z.object({
  confirm: z
    .string({ error: 'Type DELETE to confirm.' })
    .trim()
    .refine((typed) => typed === 'DELETE', 'Type DELETE to confirm.'),
});
