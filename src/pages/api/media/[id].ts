// Serving a picture (MEDIA-01). Only a member who can see its activity or group gets it, through the
// images table's row-level security, and a hidden picture is never served, even to moderators. Its
// cache is private, since the picture belongs to a member's view of FABA, and short, so a picture a
// moderator hides goes quickly. After that, a browser whose copy is still current hears "not
// changed" (304) instead of getting the picture again (UI-27). Cards ask for its small copy
// (?size=thumb, UI-03), and covers and banners for its medium copy on a phone (?size=medium,
// UI-27). A picture added without JavaScript, or before UI-27, has none, so they get the picture.
import type { APIRoute } from 'astro';
import { env } from 'cloudflare:workers';
import { mediumKey, thumbKey } from '../../../lib/media';

export const prerender = false;

const UUID = /^[0-9a-f-]{36}$/i;

/** Whether an If-None-Match header names `etag`, ignoring the weak W/ prefix. */
const names = (header: string | null, etag: string) =>
  !!header &&
  header
    .split(',')
    .map((tag) => tag.trim().replace(/^W\//, ''))
    .some((tag) => tag === '*' || tag === etag.replace(/^W\//, ''));

export const GET = (async ({ params, locals, url, request }) => {
  if (!locals.user || !UUID.test(params.id ?? '')) return new Response(null, { status: 404 });

  const { data: image } = await locals.supabase
    .from('images')
    .select('r2_key, content_type')
    .eq('id', params.id!)
    .is('hidden_at', null)
    .maybeSingle();
  if (!image) return new Response(null, { status: 404 });

  const bucket = (env as unknown as { MEDIA: MediaBucket }).MEDIA;
  const size = url.searchParams.get('size');
  const copy =
    size === 'thumb' ? thumbKey(image.r2_key) : size === 'medium' ? mediumKey(image.r2_key) : null;
  const object = (copy ? await bucket.get(copy) : null) ?? (await bucket.get(image.r2_key));
  if (!object) return new Response(null, { status: 404 });

  const headers = {
    'Content-Type': object.httpMetadata?.contentType ?? image.content_type,
    'Cache-Control': 'private, max-age=300',
    ETag: object.httpEtag,
    'X-Content-Type-Options': 'nosniff',
  };
  if (names(request.headers.get('If-None-Match'), object.httpEtag)) {
    await object.body.cancel();
    return new Response(null, { status: 304, headers });
  }
  return new Response(object.body, { headers });
}) satisfies APIRoute;
