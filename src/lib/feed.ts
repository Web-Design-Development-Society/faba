// The feed's pages (ACT-01). A cursor is the start time and id of the last activity on the page
// before, as get_feed() takes them. A category's pages stay in it (ACT-06).
import { z } from 'astro/zod';

const cursor = z.object({ after: z.iso.datetime({ offset: true }), id: z.uuid() });

/** The cursor in a Show more link, or nothing for the first page or a link that's been changed. */
export function readCursor(params: URLSearchParams) {
  const parsed = cursor.safeParse(Object.fromEntries(params));
  return parsed.success ? { after_starts_at: parsed.data.after, after_id: parsed.data.id } : {};
}

/** The query of the Show more link after `last`, in `category` if the page is. */
export function nextPage(last: { starts_at: string; id: string }, category?: string): string {
  const query = new URLSearchParams({ after: last.starts_at, id: last.id });
  if (category) query.set('cat', category);
  return `?${query}`;
}
