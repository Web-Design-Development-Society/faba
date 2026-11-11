// The offline state (PWA-01, design document section 7.13): a slim banner while the device is
// offline, and forms can't be sent, so nothing fails silently. What's typed stays on the page. It
// also registers the service worker, which only shows the offline page when a page can't load.
const banner = document.querySelector<HTMLElement>('[data-offline]');

function update() {
  const offline = !navigator.onLine;
  if (banner) banner.hidden = !offline;
  for (const control of document.querySelectorAll<HTMLButtonElement | HTMLInputElement>(
    'main form button, main form input[type="submit"]'
  )) {
    control.disabled = offline;
  }
}

window.addEventListener('online', update);
window.addEventListener('offline', update);
update();

if ('serviceWorker' in navigator) {
  navigator.serviceWorker.register('/sw.js').catch(() => {
    // The page works without it, so a failed registration is ignored.
  });
}
