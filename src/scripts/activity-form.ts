// The activity form's extras with JavaScript (ACT-03, ACT-04): quick date picks, checking the time
// rules before posting, and restoring the create form's draft. The form works without them, and
// the server checks everything again.
import { rexburgInstant } from '../lib/time';
import { clearDraft, loadDraft, saveDraft } from './activity-draft';

const form = document.querySelector<HTMLFormElement>('form[data-activity-form]');
if (form) enhance(form);

function enhance(form: HTMLFormElement) {
  const input = (name: string) => form.elements.namedItem(name) as HTMLInputElement;
  const [date, start, end] = [input('date'), input('start_time'), input('end_time')];

  const picks = form.querySelector<HTMLElement>('[data-quick-dates]')!;
  picks.hidden = false;
  picks.addEventListener('click', (event) => {
    const pick = (event.target as Element).closest<HTMLButtonElement>('button[data-date]');
    if (!pick) return;
    date.value = pick.dataset.date!;
    date.dispatchEvent(new Event('input', { bubbles: true }));
  });

  // "In the future" depends on when Post is pressed, so the check runs then.
  form.querySelector('button[type="submit"]')!.addEventListener('click', () => {
    start.setCustomValidity('');
    end.setCustomValidity('');
    if (!date.value || !start.value) return;
    const startsAt = rexburgInstant(date.value, start.value);
    if (startsAt <= new Date()) start.setCustomValidity('Pick a time in the future.');
    if (end.value && rexburgInstant(date.value, end.value) <= startsAt) {
      end.setCustomValidity('End after the start time.');
    }
  });

  // Only the create form keeps a draft. The edit form starts from what's saved (ACT-04).
  if (!('draft' in form.dataset)) return;

  // After a failed post the server shows what was typed, which is newer than any draft.
  const typed = 'typed' in form.dataset;
  const draft = typed ? null : loadDraft();
  if (draft) {
    for (const [name, value] of Object.entries(draft)) {
      const field = form.elements.namedItem(name) as HTMLInputElement | RadioNodeList | null;
      if (field) field.value = value;
    }
    if (draft.end_time || draft.cost_note) form.querySelector('details')!.open = true;
    const notice = document.querySelector<HTMLElement>('[data-draft-notice]')!;
    notice.hidden = false;
    notice.querySelector('button')!.addEventListener('click', () => {
      clearDraft();
      form.reset();
      notice.hidden = true;
    });
  }
  if (typed) saveDraft(form);
  form.addEventListener('input', () => saveDraft(form));
}
