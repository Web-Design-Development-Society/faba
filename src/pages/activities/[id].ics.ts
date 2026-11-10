// An activity as an .ics file for the member's own calendar (ACT-08, design document section
// 8.13). The middleware sends anyone signed out to sign in first, and keeps the file out of every
// cache. It reads the activity as the member, so one they can't see isn't found. Its details for
// attendees go in only when the member's answer is going, the organizer's included (ACT-09).
import type { APIRoute } from 'astro';
import { SITE_URL } from 'astro:env/server';
import { icsFile, icsFilename } from '../../lib/calendar';

export const prerender = false;

export const GET = (async ({ params, locals }) => {
  const { supabase, user } = locals;
  if (!user) return new Response('Sign in first.', { status: 401 });

  // An id that isn't a UUID is an error, so it isn't found either.
  const { data: activity } = await supabase
    .from('activities')
    .select(
      `id, title, description, starts_at, ends_at, location_name, status, version,
      mine:rsvps(status), private:activity_private_details(details)`
    )
    .eq('id', params.id!)
    .eq('mine.user_id', user.id)
    .maybeSingle();
  if (!activity) return new Response("This activity isn't available.", { status: 404 });

  const going = activity.mine[0]?.status === 'going';
  const file = icsFile(
    {
      id: activity.id,
      title: activity.title,
      startsAt: new Date(activity.starts_at),
      endsAt: activity.ends_at ? new Date(activity.ends_at) : null,
      place: activity.location_name,
      description: activity.description,
      url: new URL(`/activities/${activity.id}`, SITE_URL).href,
      version: activity.version,
      cancelled: activity.status === 'cancelled',
      privateDetails: going ? activity.private?.details : null,
    },
    new Date()
  );
  return new Response(file, {
    headers: {
      'Content-Type': 'text/calendar; charset=utf-8',
      'Content-Disposition': `attachment; filename="${icsFilename(activity.title)}"`,
    },
  });
}) satisfies APIRoute;
