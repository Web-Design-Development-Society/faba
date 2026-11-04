// Toasts in the page's role="status" message (design document section 7.8). Each shows for 5
// seconds, and stays while it's hovered or focused, so there's time to reach Undo.

const status = document.querySelector<HTMLElement>('[data-status]');
if (status) status.dataset.toast = '';

const SHOWN = 5000;
let timer: ReturnType<typeof setTimeout> | undefined;

function hideLater(delay = SHOWN) {
  clearTimeout(timer);
  timer = setTimeout(() => {
    if (status?.matches(':hover, :focus-within')) hideLater(1000);
    else status?.replaceChildren();
  }, delay);
}

/** Shows `message`, and a button such as Undo when there's an `action`. */
export function toast(message: string, action?: { label: string; run: () => void }) {
  if (!status) return;
  status.replaceChildren(message);
  if (action) {
    const button = document.createElement('button');
    button.type = 'button';
    button.textContent = action.label;
    button.addEventListener('click', () => {
      status.replaceChildren();
      action.run();
    });
    status.append(button);
  }
  hideLater();
}

// A message from the server, such as "Posted!", goes the same way.
if (status?.textContent?.trim()) hideLater();
else status?.replaceChildren();
