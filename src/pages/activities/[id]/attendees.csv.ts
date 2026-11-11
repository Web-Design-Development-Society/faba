// Everyone going to an activity, as a CSV file (RSVP-09). Only those who can manage its attendee
// list get it, and it has names only: no guest counts, and nobody suspended.
import type { APIRoute } from 'astro';

// Spreadsheets read a name that starts like a formula as one, so it gets a quote in front.
const cell = (name: string) => {
  const safe = /^[=+\-@\t\r]/.test(name) ? `'${name}` : name;
  return `"${safe.replaceAll('"', '""')}"`;
};

export const GET: APIRoute = async ({ params, locals }) => {
  const { supabase, user } = locals;
  if (!user) return new Response('Sign in first.', { status: 401 });

  const { data, error } = await supabase.rpc('attendee_names', { activity_id: params.id! });
  if (error) {
    return new Response("This isn't available to export.", {
      status: error.code === '42501' ? 403 : 404,
    });
  }

  const lines = ['"Name"', ...(data ?? []).map(cell)];
  return new Response(`${lines.join('\r\n')}\r\n`, {
    headers: {
      'Content-Type': 'text/csv; charset=utf-8',
      'Content-Disposition': `attachment; filename="attendees-${params.id}.csv"`,
    },
  });
};
