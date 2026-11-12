// Downloading my data (PRIV-01): everything FABA holds about the signed-in member, as a JSON file.
// The database builds it from the member's own rows only and rate-limits it (three a day), so a
// request past the limit gets a 429 with the reason.
import type { APIRoute } from 'astro';

export const prerender = false;

export const GET: APIRoute = async ({ locals }) => {
  if (!locals.user) {
    return new Response('Sign in to download your data.', { status: 401 });
  }

  const { data, error } = await locals.supabase.rpc('export_my_data');

  // 53400 is the database's "limit exceeded", which the export raises when it's rate limited.
  if (error?.code === '53400') {
    return new Response('You can download your data three times a day. Try again tomorrow.', {
      status: 429,
      headers: { 'Retry-After': '3600' },
    });
  }
  if (error || !data) {
    return new Response('Your data is not available right now. Try again later.', { status: 500 });
  }

  return new Response(JSON.stringify(data, null, 2), {
    headers: {
      'Content-Type': 'application/json; charset=utf-8',
      'Content-Disposition': 'attachment; filename="faba-my-data.json"',
      'Cache-Control': 'no-store',
    },
  });
};
