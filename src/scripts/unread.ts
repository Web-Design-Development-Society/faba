// The Alerts badge (NOTIF-01). The page shows the unread count when it loads. While the page is
// visible, this asks for it again every 60 seconds, and as soon as the page comes back into view.
// A hidden page doesn't ask.
import { badge } from '../lib/notifications';

const MINUTE = 60 * 1000;
const link = document.querySelector<HTMLAnchorElement>('[data-alerts]');
let timer: ReturnType<typeof setInterval> | undefined;

async function refresh() {
  try {
    const response = await fetch('/api/notifications/unread-count');
    if (!response.ok) return;
    const { count } = (await response.json()) as { count: number };
    const shown = link!.querySelector<HTMLElement>('[data-badge]')!;
    shown.querySelector('[data-count]')!.textContent = badge(count);
    shown.hidden = count === 0;
  } catch {
    // Offline for now. The next minute tries again.
  }
}

function poll() {
  clearInterval(timer);
  if (document.visibilityState === 'visible') timer = setInterval(refresh, MINUTE);
}

if (link) {
  document.addEventListener('visibilitychange', () => {
    if (document.visibilityState === 'visible') void refresh();
    poll();
  });
  poll();
}
