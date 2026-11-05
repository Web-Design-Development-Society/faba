// Astro Actions, one file per domain (design document section 9.4).
import { activities } from './activities';
import { moderation } from './moderation';
import { profile } from './profile';
import { reports } from './reports';
import { rsvps } from './rsvps';

export const server = { activities, moderation, profile, reports, rsvps };
