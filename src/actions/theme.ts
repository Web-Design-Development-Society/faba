// The theme a member chooses on Me (UI-34), kept on this device in a cookie for a year. Match device
// takes the cookie away, so FABA follows the device again (UI-33).
import { ActionError, defineAction } from 'astro:actions';
import { z } from 'astro/zod';
import { authCookieOptions } from '../lib/server/auth';
import { THEME_COOKIE, THEMES } from '../lib/theme';

const YEAR = 60 * 60 * 24 * 365;

export const theme = {
  /** Keeps Light or Dark on this device, or follows the device again. */
  choose: defineAction({
    accept: 'form',
    input: z.object({ theme: z.enum(THEMES) }),
    handler: async ({ theme }, { cookies, locals, url }) => {
      if (!locals.user) throw new ActionError({ code: 'UNAUTHORIZED' });

      if (theme === 'device') cookies.delete(THEME_COOKIE, { path: '/' });
      else cookies.set(THEME_COOKIE, theme, { ...authCookieOptions(url), maxAge: YEAR });
      return { theme };
    },
  }),
};
