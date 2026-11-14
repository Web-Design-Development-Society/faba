// Removing the member's own profile photo (UI-11), from Edit profile's Remove photo. Postgres takes
// it off the profile, which goes back to the Google photo or initials, and the Worker deletes its
// files, so it isn't kept. It works without JavaScript and comes back to Edit profile.
import type { APIRoute } from 'astro';
import { env } from 'cloudflare:workers';
import { thumbKey } from '../../../lib/media';
import { setFlash } from '../../../lib/server/flash';

export const prerender = false;

export const POST = (async ({ locals, cookies, url, redirect }) => {
  if (!locals.user) return redirect('/auth/login', 303);

  const { data: removed, error } = await locals.supabase.rpc('remove_profile_photo');
  if (error) {
    setFlash(cookies, url, 'upload_failed');
    return redirect('/me/edit#picture', 303);
  }
  if (typeof removed === 'string') {
    await (env as unknown as { MEDIA: MediaBucket }).MEDIA.delete([removed, thumbKey(removed)]);
  }
  setFlash(cookies, url, 'photo_removed');
  return redirect('/me/edit', 303);
}) satisfies APIRoute;
