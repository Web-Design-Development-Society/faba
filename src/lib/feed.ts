// The feed's pages (ACT-01). A cursor is the start time and id of the last activity on the page
// before, as get_feed() takes them. A category's pages stay in it (ACT-06). So do its dates
// (SRCH-02).
import { z } from 'astro/zod';
import { datesRange, whenRange, WHENS, type StartRange, type When } from './time';

const cursor = z.object({ after: z.iso.datetime({ offset: true }), id: z.uuid() });

/** The cursor in a Show more link, or nothing for the first page or a link that's been changed. */
export function readCursor(params: URLSearchParams) {
  const parsed = cursor.safeParse(Object.fromEntries(params));
  return parsed.success ? { after_starts_at: parsed.data.after, after_id: parsed.data.id } : {};
}

/** The page's `filters` that are set, as a query, such as `cat=outdoors&when=weekend`. */
export function filterQuery(filters: Record<string, string | undefined>): string {
  const set = Object.entries(filters).filter((entry): entry is [string, string] => !!entry[1]);
  return new URLSearchParams(set).toString();
}

/** The query of the Show more link after `last`, keeping the page's `filters` that are set. */
export function nextPage(
  last: { starts_at: string; id: string },
  filters: Record<string, string | undefined> = {}
): string {
  const query = new URLSearchParams({ after: last.starts_at, id: last.id });
  for (const [name, value] of Object.entries(filters)) if (value) query.set(name, value);
  return `?${query}`;
}

const dates = z
  .object({ from: z.iso.date().optional(), to: z.iso.date().optional() })
  .refine(({ from, to }) => (from || to) && !(from && to && from > to));

/**
 * The date filter in a link (SRCH-02), with the start times it covers at `now`, as get_feed() and
 * search_activities() take them: a chip, as in ?when=weekend, or dates, as in
 * ?from=2026-11-20&to=2026-11-22, where either can be left out. Dates win over a chip, and a link
 * that's been changed has neither.
 */
export function readDates(
  params: URLSearchParams,
  now: Date
): { when?: When; from?: string; to?: string; starts_from?: string; starts_before?: string } {
  const range = (dates: Partial<StartRange>) => ({
    starts_from: dates.from?.toISOString(),
    starts_before: dates.before?.toISOString(),
  });
  const custom = dates.safeParse({
    from: params.get('from') || undefined,
    to: params.get('to') || undefined,
  });
  if (custom.success) {
    const { from, to } = custom.data;
    return {
      ...custom.data,
      ...range({
        from: from ? datesRange(from, from).from : undefined,
        before: to ? datesRange(to, to).before : undefined,
      }),
    };
  }
  const when = params.get('when');
  if (when && Object.hasOwn(WHENS, when)) {
    return { when: when as When, ...range(whenRange(when as When, now)) };
  }
  return {};
}
