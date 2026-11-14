// Home's feed (ACT-01). Show more adds the next page below the cards, without leaving the page.
// Without JavaScript, it opens the next page. A note says when Rexburg's clock isn't the viewer's.
import { TIME_ZONE } from '../lib/time';

const offset = (timeZone?: string) =>
  new Intl.DateTimeFormat('en-US', { timeZone, timeZoneName: 'longOffset' })
    .formatToParts()
    .find(({ type }) => type === 'timeZoneName')?.value;

const note = document.querySelector<HTMLElement>('[data-zone-note]');
if (note && offset() !== offset(TIME_ZONE)) note.hidden = false;

const more = document.querySelector<HTMLAnchorElement>('[data-more]');

more?.addEventListener('click', async (event) => {
  event.preventDefault();
  more.textContent = 'Loading…';
  try {
    const response = await fetch(more.href);
    if (!response.ok) throw new Error(`Show more got ${response.status}`);
    const page = new DOMParser().parseFromString(await response.text(), 'text/html');
    const feed = document.querySelector('[data-feed]')!;
    let first: HTMLElement | undefined;
    // A day that carries on from the last page joins its list.
    for (const day of page.querySelectorAll<HTMLElement>('[data-feed] > section')) {
      const cards = [...day.querySelectorAll('li')];
      first ??= cards[0];
      const list = feed.querySelector(`[data-day="${day.dataset.day}"] ul`);
      if (list) list.append(...cards);
      else feed.append(day);
    }
    const next = page.querySelector('[data-more]')?.getAttribute('href');
    if (next) {
      more.href = next;
      more.textContent = 'Show more';
    } else {
      more.remove();
    }
    // Keyboard and screen reader users carry on from the first new card.
    first?.querySelector('a')?.focus();
  } catch {
    location.href = more.href;
  }
});
