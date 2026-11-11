// How a series repeats (REC-01, design document section 7.7): the create form's Repeats choices,
// and the words for a series on a card and its activity's page. The database makes the dates.

/** The create form's Repeats choices, as create_series() takes them, and Doesn't repeat. */
export const REPEATS = {
  none: "Doesn't repeat",
  weekly: 'Weekly',
  biweekly: 'Every 2 weeks',
  monthly_date: 'Monthly on the same date',
  monthly_nth: 'Monthly on the same weekday',
} as const;

export type Repeats = keyof typeof REPEATS;

/** How a series repeats. */
export type Freq = Exclude<Repeats, 'none'>;

const WEEKDAYS = ['Sunday', 'Monday', 'Tuesday', 'Wednesday', 'Thursday', 'Friday', 'Saturday'];
const ORDINALS = ['1st', '2nd', '3rd', '4th', 'last'];

/** The weekday `date`, such as `2026-11-10`, falls on: `Tuesday`. */
export function weekdayName(date: string): string {
  return WEEKDAYS[new Date(`${date}T12:00:00Z`).getUTCDay()];
}

/**
 * The edit form's warning when This and future dates moves a series from `from`'s weekday to
 * `to`'s (REC-02), or nothing when it's the same weekday.
 */
export function weekdayWarning(from: string, to: string): string {
  const [was, now] = [weekdayName(from), weekdayName(to)];
  return was === now
    ? ''
    : `Future dates move from ${was}s to ${now}s. People going stay going, and they're told.`;
}

/** The day of `date`, such as `2026-11-07`, as the ordinal `7th`. */
export function ordinalDay(date: string): string {
  const day = Number(date.slice(8, 10));
  const suffix =
    day % 10 === 1 && day !== 11
      ? 'st'
      : day % 10 === 2 && day !== 12
        ? 'nd'
        : day % 10 === 3 && day !== 13
          ? 'rd'
          : 'th';
  return `${day}${suffix}`;
}

/**
 * Which weekday of its month `date` is, such as `2nd Tuesday` for `2026-11-10`. A 5th one is the
 * `last`, as the series falls on it every month.
 */
export function nthWeekday(date: string): string {
  const day = Number(date.slice(8, 10));
  return `${ORDINALS[Math.min(Math.ceil(day / 7), 5) - 1]} ${weekdayName(date)}`;
}

/**
 * The monthly choices' labels for a first date, such as `Monthly on the 10th` and `Monthly on the
 * 2nd Tuesday`, or the general ones without a date.
 */
export function monthlyLabels(date?: string): Pick<Record<Repeats, string>, Freq> {
  return {
    weekly: REPEATS.weekly,
    biweekly: REPEATS.biweekly,
    monthly_date: date ? `Monthly on the ${ordinalDay(date)}` : REPEATS.monthly_date,
    monthly_nth: date ? `Monthly on the ${nthWeekday(date)}` : REPEATS.monthly_nth,
  };
}

/** A card's word for a series: `Weekly`, `Every 2 weeks` or `Monthly`. */
export function repeatsBadge(freq: string): string {
  return freq === 'weekly' ? 'Weekly' : freq === 'biweekly' ? 'Every 2 weeks' : 'Monthly';
}

/**
 * How a series repeats, on its activity's page: `Repeats weekly`, `Repeats every 2 weeks`,
 * `Repeats monthly on the 10th` or `Repeats monthly on the 2nd Tuesday`, from its first date.
 */
export function repeatsSentence(freq: string, startDate: string): string {
  const labels = monthlyLabels(startDate);
  const label = freq in labels ? labels[freq as Freq] : 'Monthly';
  return `Repeats ${label.charAt(0).toLowerCase()}${label.slice(1)}`;
}
