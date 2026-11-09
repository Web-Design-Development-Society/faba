// The unread count for the Alerts badge (NOTIF-01), which src/scripts/unread.ts asks for every
// minute while the page is visible. The middleware has already read it with the session context,
// using the partial index on unread rows, so this adds no query of its own.
import type { APIRoute } from 'astro';

export const prerender = false;

export const GET = (({ locals }) => {
  if (!locals.member) return Response.json({ error: 'Sign in first.' }, { status: 401 });
  return Response.json({ count: locals.member.unread_count });
}) satisfies APIRoute;
