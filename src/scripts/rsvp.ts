// I'm in without leaving the page (RSVP-01, design document section 7.8). The button says ✓ Going,
// and the count and faces count the member, before the save finishes. Then "You're going." shows
// with Undo. If saving fails, they go back and the toast says why. Without JavaScript, the form
// posts and the page comes back.
import { actions } from 'astro:actions';
import { toast } from './toast';

const FAILED = "Your RSVP couldn't be saved. Please try again.";

// The member's own face, from the page.
const face = document.querySelector<HTMLTemplateElement>('template[data-my-face]');

/** Shows the member going or not on the form, and in every count and row of faces for `id`. */
function show(form: HTMLFormElement, id: string, going: boolean) {
  const button = form.querySelector('button')!;
  button.textContent = going ? '✓ Going' : "I'm in";
  // ✓ Going does nothing until RSVP-02, but keeps the focus.
  if (going) button.setAttribute('aria-disabled', 'true');
  else button.removeAttribute('aria-disabled');

  for (const row of document.querySelectorAll<HTMLElement>(`[data-going="${id}"]`)) {
    const count = row.querySelector('[data-count]')!;
    count.textContent = String(Number(count.textContent) + (going ? 1 : -1));
    const mine = row.querySelector('[data-mine]');
    if (!going) mine?.remove();
    else if (face && !mine && row.querySelectorAll('.avatar').length < Number(row.dataset.faces)) {
      const clone = face.content.firstElementChild!.cloneNode(true) as Element;
      clone.setAttribute('data-mine', '');
      count.before(clone);
    }
  }
}

/** Saves the RSVP, showing it at once. True when it saved. */
async function save(form: HTMLFormElement, status: 'going' | 'not_going') {
  const body = new FormData(form);
  body.set('status', status);
  const id = String(body.get('activity_id'));
  show(form, id, status === 'going');
  const { data, error } = await actions.rsvps
    .set(body)
    .catch(() => ({ data: undefined, error: { message: FAILED } }));
  if (data) {
    // The saved count, which also counts anyone else who said I'm in meanwhile.
    for (const count of document.querySelectorAll(`[data-going="${id}"] [data-count]`)) {
      count.textContent = String(data.going_count);
    }
    return true;
  }
  show(form, id, status !== 'going');
  toast(error.message);
  return false;
}

document.addEventListener('submit', async (event) => {
  const form = event.target;
  if (!(form instanceof HTMLFormElement) || !form.matches('[data-rsvp]')) return;
  event.preventDefault();
  if (form.querySelector('[aria-disabled]')) return;

  if (await save(form, 'going')) {
    toast("You're going.", {
      label: 'Undo',
      run: async () => {
        form.querySelector('button')!.focus();
        if (await save(form, 'not_going')) toast('Undone.');
      },
    });
  }
});
