// I'm in, Maybe, Can't make it and guests without leaving the page (RSVP-01, RSVP-02, RSVP-05 and
// RSVP-06, design document section 7.8). The button, the counts, the faces and who's going change
// before the save finishes. After I'm in, "You're going." shows with Undo. If saving fails, they change back and
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

/** Shows the guest total for `id`, such as "(+5 guests)", or nothing for none. */
function guestTotal(id: string, change: number) {
  for (const total of document.querySelectorAll<HTMLElement>(`[data-guest-total="${id}"]`)) {
    const guests = Number(total.dataset.value ?? 0) + change;
    total.dataset.value = String(guests);
    total.textContent = ` (+${guests} ${guests === 1 ? 'guest' : 'guests'})`;
    total.hidden = guests === 0;
  }
}

/**
 * Shows the member's answer, and the guests they're bringing, in every RSVP button, sheet, count,
 * row of faces and list for `id`. Without a number, a member going keeps their guests.
 */
function show(id: string, status: Status, guests?: number) {
  const controls = document.querySelectorAll<HTMLElement>(`[data-rsvp="${id}"]`);
  const was = (controls[0]?.dataset.status ?? 'not_going') as Status;
  const had = Number(controls[0]?.dataset.guests ?? 0);
  const mine = status === 'going' ? (guests ?? (was === 'going' ? had : 0)) : 0;
  guestTotal(id, mine - had);
  for (const control of controls) {
    control.dataset.status = status;
    control.dataset.guests = String(mine);
    const field = control.querySelector<HTMLInputElement>('input[name="guests"]');
    if (field) field.value = String(mine);
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
async function save(id: string, status: Status, guests?: number) {
  const control = document.querySelector<HTMLElement>(`[data-rsvp="${id}"]`);
  const was = (control?.dataset.status ?? 'not_going') as Status;
  const had = Number(control?.dataset.guests ?? 0);
  const body = new FormData();
  body.set('activity_id', id);
  body.set('status', status);
  if (guests !== undefined) body.set('guests', String(guests));
  show(id, status, guests);
  const { data, error } = await actions.rsvps
    .set(body)
    .catch(() => ({ data: undefined, error: { message: FAILED } }));
  if (data) {
    // The saved count, which also counts anyone else who said I'm in meanwhile. A row's first count
    // is its going count. The maybe count after it changes only as the member does.
    for (const row of document.querySelectorAll(`[data-going="${id}"]`)) {
      row.querySelector('[data-count]')!.textContent = String(data.going_count);
    }
    return true;
  }
  show(id, was, had);
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
  const data = new FormData(form);
  const status = data.get('status') as Status;
  const was = (control.dataset.status ?? 'not_going') as Status;
  const had = Number(control.dataset.guests ?? 0);

  // A choice in the sheet closes it, and the member's own answer changes nothing. So does saving
  // the guests they're already bringing.
  const sheet = form.closest('dialog');
  if (data.has('guests')) {
    const guests = Number(data.get('guests'));
    sheet?.close();
    if (status === was && String(guests) === control.dataset.guests) return;
    if (await save(id, 'going', guests)) {
      toast(
        guests ? `You're going with ${guests} ${guests === 1 ? 'guest' : 'guests'}.` : SAVED.going
      );
    }
  } else if (sheet) {
    sheet.close();
    if (status !== was && (await save(id, status))) toast(SAVED[status]);
  } else if (await save(id, 'going')) {
    const button = control.querySelector<HTMLElement>(':scope > form button')!;
    toast(SAVED.going, {
      label: 'Undo',
      run: async () => {
        button.focus();
        if (await save(id, was, had)) toast('Undone.');
      },
    });
  }
});
