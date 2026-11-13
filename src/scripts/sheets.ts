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

// A tap outside a sheet closes it. Sheet.astro asks for that with closedby="any", which older
// browsers, such as an older Safari, don't have, so this does it there. A tap on the dimmed page
// lands on the dialog itself, outside its box; one on the sheet's own padding lands inside it.
if (!('closedBy' in HTMLDialogElement.prototype)) {
  document.addEventListener('click', (event) => {
    const sheet = event.target;
    if (!(sheet instanceof HTMLDialogElement) || !sheet.open) return;
    const box = sheet.getBoundingClientRect();
    const inside =
      event.clientX >= box.left &&
      event.clientX <= box.right &&
      event.clientY >= box.top &&
      event.clientY <= box.bottom;
    if (!inside) sheet.close();
  });
}

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
