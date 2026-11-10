// An activity's details for attendees (ACT-09) without leaving the page. When the member's answer
// changes, src/scripts/rsvp.ts says so, and this asks for the details again. RLS gives them only
// to members going, so they show after I'm in and the note comes back after Can't make it. Without
// JavaScript, the page comes back after an answer, with or without them.
import { actions } from 'astro:actions';
import { linkify } from '../lib/links';
import type { RsvpChange } from './rsvp';

// The last answer's request, so an earlier one that finishes later is ignored.
let latest = 0;

document.addEventListener('rsvp-change', async (event) => {
  const { id } = (event as CustomEvent<RsvpChange>).detail;
  const section = document.querySelector<HTMLElement>(`[data-private-details="${id}"]`);
  if (!section) return;

  const request = ++latest;
  const { data } = await actions.activities
    .privateDetails({ activity_id: id })
    .catch(() => ({ data: undefined }));
  // If asking fails, the page stays as it is until it's opened again.
  if (!data || request !== latest) return;

  const details = section.querySelector<HTMLElement>('[data-details]')!;
  details.replaceChildren(
    ...linkify(data.details ?? '').map(({ text, href }) => {
      if (!href) return text;
      const link = document.createElement('a');
      link.href = href;
      link.rel = 'nofollow ugc noopener';
      link.textContent = text;
      return link;
    })
  );
  details.hidden = !data.details;
  section.querySelector<HTMLElement>('[data-note]')!.hidden = !!data.details;
});
