// Serving a picture (MEDIA-01). Only a member who can see its activity or group gets it, through the
// images table's row-level security, and a hidden picture is never served, even to moderators. Its
// cache is private, since the picture belongs to a member's view of FABA. Cards ask for its small
// copy (?size=thumb, UI-03). A picture added without JavaScript has none, so they get the picture.
import type { APIRoute } from 'astro';
import { env } from 'cloudflare:workers';
import { thumbKey } from '../../../lib/media';

export const prerender = false;

const UUID = /^[0-9a-f-]{36}$/i;

export const GET = (async ({ params, locals, url }) => {
  if (!locals.user || !UUID.test(params.id ?? '')) return new Response(null, { status: 404 });

  const { data: image } = await locals.supabase
    .from('images')
    .select('r2_key, content_type')
    .eq('id', params.id!)
    .is('hidden_at', null)
    .maybeSingle();
  if (!image) return new Response(null, { status: 404 });

  const bucket = (env as unknown as { MEDIA: MediaBucket }).MEDIA;
  const object =
    (url.searchParams.get('size') === 'thumb' ? await bucket.get(thumbKey(image.r2_key)) : null) ??
    (await bucket.get(image.r2_key));
  if (!object) return new Response(null, { status: 404 });

  return new Response(object.body, {
    headers: {
      'Content-Type': object.httpMetadata?.contentType ?? image.content_type,
      'Cache-Control': 'private, max-age=300',
      ETag: object.httpEtag,
      'X-Content-Type-Options': 'nosniff',
    },
  });
}) satisfies APIRoute;
