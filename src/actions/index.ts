// Astro Actions, one file per domain (design document section 9.4).
import { activities } from './activities';
import { profile } from './profile';

export const server = { activities, profile };
