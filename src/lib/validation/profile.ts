// Limits for profile fields, shared by forms and Actions (design document section 9.9). They
// match the CHECK constraints on public.profiles.
import { z } from 'astro/zod';

export const DISPLAY_NAME = { min: 2, max: 50 };

export const displayName = z
  .string()
  .trim()
  .min(DISPLAY_NAME.min, 'Use at least 2 characters.')
  .max(DISPLAY_NAME.max, 'Use 50 characters or fewer.');
