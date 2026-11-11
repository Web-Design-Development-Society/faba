// A member's calendar feed (CAL-01): the activities they're going to, as an iCal file that
// calendar apps subscribe to. Calendar apps don't sign in, so the token in the link is the
// credential, and the middleware lets this path through. A wrong or reset link gets nothing, and
// too many requests get a 429 (the database limits each feed).
import type { APIRoute } from 'astro';
import { SITE_URL } from 'astro:env/server';
import { icsFeed, type CalendarEvent } from '../../lib/calendar';
import { hashFeedToken } from '../../lib/calendar-feed';

export const prerender = false;

export const GET = (async ({ params, locals }) => {
  const token = params.token ?? '';
  const { data, error } = await locals.supabase.rpc('calendar_feed_events', {
    token_hash: await hashFeedToken(token),
  });

  // 53400 is the database's "limit exceeded", which the feed raises when it's rate limited.
  if (error?.code === '53400') {
    return new Response('Too many requests. Try again later.', {
      status: 429,
      headers: { 'Retry-After': '3600' },
    });
  }
  if (error || !data) {
    return new Response("This calendar link isn't available.", { status: 404 });
  }

  const events: CalendarEvent[] = data.map((activity) => ({
    id: activity.id,
    title: activity.title,
    startsAt: new Date(activity.starts_at),
    endsAt: activity.ends_at ? new Date(activity.ends_at) : null,
    place: activity.location_name,
    description: activity.description,
    url: new URL(`/activities/${activity.id}`, SITE_URL).href,
    version: activity.version,
    cancelled: activity.status === 'cancelled',
  }));

  return new Response(icsFeed(events, new Date()), {
    headers: { 'Content-Type': 'text/calendar; charset=utf-8' },
  });
}) satisfies APIRoute;
