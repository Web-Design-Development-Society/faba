/* global self, caches */
// FABA's service worker (PWA-01, design document section 7.13). It does one thing: when a page
// can't load because the device is offline, it shows the offline page. It caches nothing else, so
// no member's pages, and nothing signed in, are ever stored on the device.
const CACHE = 'faba-offline-v1';
const OFFLINE = '/offline.html';

self.addEventListener('install', (event) => {
  event.waitUntil(
    caches
      .open(CACHE)
      .then((cache) => cache.add(new Request(OFFLINE, { cache: 'reload' })))
      .then(() => self.skipWaiting())
  );
});

self.addEventListener('activate', (event) => {
  event.waitUntil(
    caches
      .keys()
      .then((keys) =>
        Promise.all(keys.filter((key) => key !== CACHE).map((key) => caches.delete(key)))
      )
      .then(() => self.clients.claim())
  );
});

// Only the member's own page loads (GET navigations on this site). Sign-in redirects to other sites,
// and form posts, are left to the browser, so nothing they do is changed.
self.addEventListener('fetch', (event) => {
  const { request } = event;
  if (request.mode !== 'navigate' || request.method !== 'GET') return;
  if (new URL(request.url).origin !== self.location.origin) return;
  event.respondWith(fetch(event.request).catch(() => caches.match(OFFLINE)));
});
