// Uploading a picture for an activity's cover, a group's banner (MEDIA-01) or the member's own
// profile photo (UI-11). It works without
// JavaScript: a form posts here, and the page it came from says what happened. The Worker checks the
// file's own bytes, stores it under a random key in the bucket, then asks Postgres to point the
// activity or group at it. Postgres checks who's allowed, and the Worker deletes the file again if
// that fails, so the bucket never keeps a picture nothing points to. With JavaScript, the device also
// sends a small copy for cards (UI-03), and for a cover or banner a medium copy for phones (UI-27),
// each kept beside it. One that isn't a picture, or is too big, is left out. A
// profile photo needs no description, since it's the member's face, and replacing it deletes the
// old one's files, so a member's old photos aren't kept.
import type { APIRoute } from 'astro';
import { env } from 'cloudflare:workers';
import {
  ALT_MAX,
  MEDIUM_MAX_BYTES,
  mediumKey,
  pictureProblem,
  sniffPicture,
  THUMB_MAX_BYTES,
  thumbKey,
} from '../../../lib/media';
import { setFlash } from '../../../lib/server/flash';

export const prerender = false;

const bucket = () => (env as unknown as { MEDIA: MediaBucket }).MEDIA;

// Where the form came from: an activity or group page, or Edit profile, and nowhere else.
const backFrom = (value: FormDataEntryValue | null) => {
  const back = typeof value === 'string' ? value : '';
  return /^\/(activities|groups)\/[A-Za-z0-9\-_/]+$/.test(back) || back === '/me/edit'
    ? back
    : null;
};

export const POST = (async ({ locals, request, cookies, url, redirect }) => {
  if (!locals.user) return redirect('/auth/login', 303);

  const form = await request.formData();
  const back = backFrom(form.get('back'));
  if (!back) return new Response('Not found.', { status: 404 });

  const kind = form.get('target');
  const target = kind === 'group' || kind === 'profile' ? kind : 'activity';
  // A profile photo is always the signed-in member's own.
  const id = target === 'profile' ? locals.user.id : String(form.get('id') ?? '');
  const alt = String(form.get('alt') ?? '').trim();
  const file = form.get('picture');
  // Back to the upload form (src/components/PictureUpload.astro), which says why. The Worker's logs
  // say why too, with the file's size and the type the browser named, and nothing about who.
  const fail = (flash: Parameters<typeof setFlash>[2]) => {
    console.warn(
      JSON.stringify({
        upload: 'refused',
        reason: flash,
        bytes: file instanceof File ? file.size : null,
        sent_as: file instanceof File ? file.type : null,
      })
    );
    setFlash(cookies, url, flash);
    return redirect(`${back}#picture`, 303);
  };

  if (!/^[0-9a-f-]{36}$/i.test(id)) return new Response('Not found.', { status: 404 });
  if (!(file instanceof File)) return fail('upload_missing');
  if (target !== 'profile' && (alt.length === 0 || alt.length > ALT_MAX)) {
    return fail('upload_alt');
  }

  const bytes = new Uint8Array(await file.arrayBuffer());
  const problem = pictureProblem(file.size, bytes);
  if (problem) {
    if (problem.startsWith('Choose')) return fail('upload_missing');
    if (problem.includes('2 MB')) return fail('upload_too_big');
    return fail('upload_type');
  }
  const type = sniffPicture(bytes)!;

  const folder = { activity: 'activities', group: 'groups', profile: 'profiles' }[target];
  const key = `${folder}/${crypto.randomUUID()}`;
  await bucket().put(key, bytes.buffer, { httpMetadata: { contentType: type } });
  /** Keeps the device's copy from `field` at `copy`, if it's a picture no bigger than `max`. */
  const keep = async (field: string, max: number, copy: string) => {
    const sent = form.get(field);
    if (!(sent instanceof File) || sent.size === 0 || sent.size > max) return;
    const made = new Uint8Array(await sent.arrayBuffer());
    const madeType = sniffPicture(made);
    if (madeType)
      await bucket().put(copy, made.buffer, { httpMetadata: { contentType: madeType } });
  };
  await keep('thumb', THUMB_MAX_BYTES, thumbKey(key));
  if (target !== 'profile') await keep('medium', MEDIUM_MAX_BYTES, mediumKey(key));

  const { data: replaced, error } =
    target === 'profile'
      ? await locals.supabase.rpc('set_profile_photo', {
          r2_key: key,
          content_type: type,
          bytes: file.size,
        })
      : target === 'group'
        ? await locals.supabase.rpc('set_group_banner', {
            group_id: id,
            r2_key: key,
            content_type: type,
            bytes: file.size,
            alt,
          })
        : await locals.supabase.rpc('set_activity_cover', {
            activity_id: id,
            r2_key: key,
            content_type: type,
            bytes: file.size,
            alt,
          });

  if (error) {
    await bucket().delete([key, thumbKey(key), mediumKey(key)]);
    return fail(
      error.message.includes('NOT_ORGANIZER') || error.message.includes('NOT_GROUP_ORGANIZER')
        ? 'upload_forbidden'
        : 'upload_failed'
    );
  }

  // A profile photo it replaced goes from the bucket too.
  if (target === 'profile' && typeof replaced === 'string') {
    await bucket().delete([replaced, thumbKey(replaced)]);
  }
  setFlash(
    cookies,
    url,
    target === 'profile' ? 'photo_saved' : target === 'group' ? 'banner_saved' : 'cover_saved'
  );
  return redirect(back, 303);
}) satisfies APIRoute;
