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

/** A page's filters, where a filter can have more than one value, such as tags (SRCH-03). */
export type Filters = Record<string, string | string[] | undefined>;

/** The page's `filters` that are set, as a query, such as `cat=outdoors&when=weekend`. */
export function filterQuery(filters: Filters): string {
  return new URLSearchParams(
    Object.entries(filters).flatMap(([name, value]) =>
      [value ?? []]
        .flat()
        .filter(Boolean)
        .map((one) => [name, one])
    )
  ).toString();
}

/** The query of the Show more link after `last`, keeping the page's `filters` that are set. */
export function nextPage(last: { starts_at: string; id: string }, filters: Filters = {}): string {
  const query = new URLSearchParams({ after: last.starts_at, id: last.id });
  const kept = filterQuery(filters);
  return kept ? `?${query}&${kept}` : `?${query}`;
}

/**
 * More filters' other filters in a link (SRCH-03): ?spots=1 for activities with spots left, and a
 * tag for each tag asked for, as in ?tag=free&tag=family-friendly, as get_feed() and
 * search_activities() take them. They leave out a tag that isn't offered, and so should the page.
 */
export function readMore(params: URLSearchParams) {
  return {
    spots: params.get('spots') === '1',
    tags: [...new Set(params.getAll('tag'))].filter((tag) => /^[a-z][a-z0-9-]*$/.test(tag)),
  };
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
