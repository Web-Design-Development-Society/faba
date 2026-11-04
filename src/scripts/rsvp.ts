// I'm in and Can't make it without leaving the page (RSVP-01 and RSVP-02, design document section
// 7.8). The button, the count and the faces change before the save finishes. After I'm in,
// "You're going." shows with Undo. If saving fails, they change back and the toast says why.
// Without JavaScript, the forms post and the page comes back.
import { actions } from 'astro:actions';
import { toast } from './toast';

const FAILED = "Your RSVP couldn't be saved. Please try again.";

// The member's own face, from the page.
const face = document.querySelector<HTMLTemplateElement>('template[data-my-face]');

/** Shows the member going or not in every RSVP button, count and row of faces for `id`. */
function show(id: string, going: boolean) {
  for (const button of document.querySelectorAll<HTMLButtonElement>(
    `[data-rsvp="${id}"] > form button`
  )) {
    // ✓ Going opens the sheet, and I'm in posts.
    button.textContent = going ? '✓ Going' : "I'm in";
    button.type = going ? 'button' : 'submit';
    if (!going) button.removeAttribute('command');
  }

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
async function save(id: string, status: 'going' | 'not_going') {
  const body = new FormData();
  body.set('activity_id', id);
  body.set('status', status);
  show(id, status === 'going');
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
  show(id, status !== 'going');
  toast(error.message);
  return false;
}

document.addEventListener('submit', async (event) => {
  const form = event.target;
  // The sheet's Going is a form that only closes it.
  if (!(form instanceof HTMLFormElement) || form.method !== 'post') return;
  const control = form.closest<HTMLElement>('[data-rsvp]');
  if (!control) return;
  event.preventDefault();
  const id = control.dataset.rsvp!;
  const button = control.querySelector<HTMLElement>(':scope > form button')!;

  if (new FormData(form).get('status') === 'not_going') {
    form.closest('dialog')!.close();
    if (await save(id, 'not_going')) toast("You're not going.");
  } else if (await save(id, 'going')) {
    toast("You're going.", {
      label: 'Undo',
      run: async () => {
        button.focus();
        if (await save(id, 'not_going')) toast('Undone.');
      },
    });
  }
});

// Safari doesn't give ✓ Going the focus back when its sheet closes.
document.addEventListener(
  'close',
  (event) => {
    const sheet = event.target;
    if (!(sheet instanceof HTMLDialogElement)) return;
    if (document.activeElement === document.body || sheet.contains(document.activeElement)) {
      sheet.closest('[data-rsvp]')?.querySelector<HTMLElement>(':scope > form button')?.focus();
    }
  },
  true
);

// ✓ Going opens its sheet. Without JavaScript, its invoker command does that. I'm in doesn't get
// one when it becomes ✓ Going, since the browser would run it as I'm in posts. Safari before 26.2
// has no invoker commands either.
document.addEventListener('click', (event) => {
  if (!(event.target instanceof Element)) return;
  const button = event.target.closest<HTMLButtonElement>('[data-rsvp] > form button');
  const sheet = button?.closest('[data-rsvp]')!.querySelector('dialog');
  if (button?.type === 'button' && sheet && !sheet.open) sheet.showModal();
});
