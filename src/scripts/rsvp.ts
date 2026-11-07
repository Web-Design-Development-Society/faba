// I'm in, Maybe and Can't make it without leaving the page (RSVP-01, RSVP-02 and RSVP-05, design
// document section 7.8). The button, the counts, the faces and who's going change before the save
// finishes. After I'm in, "You're going." shows with Undo. If saving fails, they change back and
// the toast says why. Without JavaScript, the forms post and the page comes back.
import { actions } from 'astro:actions';
import './sheets';
import { toast } from './toast';

const FAILED = "Your RSVP couldn't be saved. Please try again.";

type Status = 'going' | 'maybe' | 'not_going';

const SAVED: Record<Status, string> = {
  going: "You're going.",
  maybe: "You're a maybe.",
  not_going: "You're not going.",
};

// The member's own face, from the page.
const face = document.querySelector<HTMLTemplateElement>('template[data-my-face]');

/** Adds `change` to each count in `selector`, and hides a maybe count of 0. */
function count(selector: string, change: number) {
  for (const row of document.querySelectorAll<HTMLElement>(selector)) {
    const count = row.querySelector('[data-count]')!;
    count.textContent = String(Number(count.textContent) + change);
    if ('maybe' in row.dataset) row.hidden = count.textContent === '0';
  }
}

/** Shows the member's answer in every RSVP button, sheet, count, row of faces and list for `id`. */
function show(id: string, status: Status) {
  const controls = document.querySelectorAll<HTMLElement>(`[data-rsvp="${id}"]`);
  const was = (controls[0]?.dataset.status ?? 'not_going') as Status;
  for (const control of controls) {
    control.dataset.status = status;
    // ✓ Going and Maybe open the sheet, and I'm in posts. I'm in doesn't get an invoker command when
    // it changes, since the browser would run it as I'm in posts. src/scripts/sheets.ts opens the
    // sheet instead.
    const button = control.querySelector<HTMLButtonElement>(':scope > form button')!;
    button.textContent = { going: '✓ Going', maybe: 'Maybe', not_going: "I'm in" }[status];
    button.type = status === 'not_going' ? 'submit' : 'button';
    if (status === 'not_going') button.removeAttribute('command');
    for (const choice of control.querySelectorAll<HTMLButtonElement>('dialog form button')) {
      const value = new FormData(choice.form!).get('status');
      choice.setAttribute('aria-pressed', String(value === status));
    }
  }
  if (was === status) return;

  // Who's going has the member in it, hidden while they're not (RSVP-03).
  for (const mine of document.querySelectorAll<HTMLElement>(
    `[data-going-list="${id}"] > [data-mine]`
  )) {
    mine.hidden = status !== 'going';
  }

  const going = Number(status === 'going') - Number(was === 'going');
  count(`[data-going="${id}"]`, going);
  count(`[data-maybe="${id}"]`, Number(status === 'maybe') - Number(was === 'maybe'));
  for (const row of document.querySelectorAll<HTMLElement>(`[data-going="${id}"]`)) {
    const mine = row.querySelector('[data-mine]');
    if (going < 0) mine?.remove();
    else if (going > 0 && face && !mine) {
      if (row.querySelectorAll('.avatar').length >= Number(row.dataset.faces)) continue;
      const clone = face.content.firstElementChild!.cloneNode(true) as Element;
      clone.setAttribute('data-mine', '');
      row.querySelector('[data-count]')!.before(clone);
    }
  }
}

/** Saves the RSVP, showing it at once. True when it saved. */
async function save(id: string, status: Status) {
  const was = (document.querySelector<HTMLElement>(`[data-rsvp="${id}"]`)?.dataset.status ??
    'not_going') as Status;
  const body = new FormData();
  body.set('activity_id', id);
  body.set('status', status);
  show(id, status);
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
  show(id, was);
  toast(error.message);
  return false;
}

document.addEventListener('submit', async (event) => {
  const form = event.target;
  if (!(form instanceof HTMLFormElement) || form.method !== 'post') return;
  const control = form.closest<HTMLElement>('[data-rsvp]');
  if (!control) return;
  event.preventDefault();
  const id = control.dataset.rsvp!;
  const status = new FormData(form).get('status') as Status;
  const was = (control.dataset.status ?? 'not_going') as Status;

  // A choice in the sheet closes it, and the member's own answer changes nothing.
  const sheet = form.closest('dialog');
  if (sheet) {
    sheet.close();
    if (status !== was && (await save(id, status))) toast(SAVED[status]);
  } else if (await save(id, 'going')) {
    const button = control.querySelector<HTMLElement>(':scope > form button')!;
    toast(SAVED.going, {
      label: 'Undo',
      run: async () => {
        button.focus();
        if (await save(id, was)) toast('Undone.');
      },
    });
  }
});
