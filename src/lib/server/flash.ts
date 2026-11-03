// One-time messages for the page after a redirect, such as "Posted!" (ACT-03). A short-lived
// cookie carries them, so they work without JavaScript and don't stay in the URL to be shared.
import type { AstroCookies } from 'astro';
import { authCookieOptions } from './auth';

export type Flash = 'posted';

const FLASH_COOKIE = 'faba-flash';

export function setFlash(cookies: AstroCookies, url: URL, flash: Flash) {
  cookies.set(FLASH_COOKIE, flash, { ...authCookieOptions(url), maxAge: 60 });
}

/** The message waiting for this page, if any. Taking it clears it. */
export function takeFlash(cookies: AstroCookies): Flash | undefined {
  const flash = cookies.get(FLASH_COOKIE)?.value;
  if (!flash) return undefined;
  cookies.delete(FLASH_COOKIE, { path: '/' });
  return flash === 'posted' ? flash : undefined;
}
