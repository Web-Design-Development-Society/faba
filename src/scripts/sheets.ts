// Bottom sheets (src/components/Sheet.astro). A button opens one with an invoker command, which
// Safari before 26.2 doesn't have, so this opens it too. It also opens it from a button that
// src/scripts/rsvp.ts made ✓ Going, which has no command. Safari doesn't give the button the focus
// back when the sheet closes, so this does.
document.addEventListener('click', (event) => {
  if (!(event.target instanceof Element)) return;
  const button = event.target.closest<HTMLButtonElement>('button[commandfor]');
  const sheet = button && document.getElementById(button.getAttribute('commandfor')!);
  if (button?.type === 'button' && sheet instanceof HTMLDialogElement && !sheet.open) {
    sheet.showModal();
  }
});

document.addEventListener(
  'close',
  (event) => {
    const sheet = event.target;
    if (!(sheet instanceof HTMLDialogElement)) return;
    if (document.activeElement === document.body || sheet.contains(document.activeElement)) {
      document.querySelector<HTMLElement>(`[commandfor="${sheet.id}"]`)?.focus();
    }
  },
  true
);
