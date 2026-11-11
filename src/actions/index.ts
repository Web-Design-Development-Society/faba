// Astro Actions, one file per domain (design document section 9.4).
import { activities } from './activities';
import { admin } from './admin';
import { calendar } from './calendar';
import { follows } from './follows';
import { groups } from './groups';
import { moderation } from './moderation';
import { notifications } from './notifications';
import { profile } from './profile';
import { reports } from './reports';
import { rsvps } from './rsvps';

export const server = {
  activities,
  admin,
  calendar,
  follows,
  groups,
  moderation,
  notifications,
  profile,
  reports,
  rsvps,
};
