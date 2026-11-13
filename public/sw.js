/* global self, caches */
// FABA's service worker (PWA-01, design document section 7.13). When a page can't load because the
// device is offline, it shows the offline page. It caches nothing else, so no member's pages, and
// nothing signed in, are ever stored on the device. It also shows pushes (NOTIF-20).
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

// Push (NOTIF-20): show what FABA sent. A newer push of the same notification replaces the older
// one. Tapping it opens /notifications/{id}, which marks it read and goes where it points.
self.addEventListener('push', (event) => {
  let message = {};
  try {
    message = event.data ? event.data.json() : {};
  } catch {
    // Not FABA's format, so it shows as a plain FABA notification.
  }
  event.waitUntil(
    self.registration.showNotification(message.title || 'FABA', {
      body: message.body || '',
      tag: message.id,
      renotify: Boolean(message.id),
      icon: '/icons/icon-192.png',
      data: { url: message.url || '/notifications' },
    })
  );
});

self.addEventListener('notificationclick', (event) => {
  event.notification.close();
  const url = new URL(event.notification.data?.url || '/notifications', self.location.origin);
  // Only FABA's own pages open.
  if (url.origin !== self.location.origin) return;
  event.waitUntil(self.clients.openWindow(url.href));
});

// Only the member's own page loads (GET navigations on this site). Sign-in redirects to other sites,
// and form posts, are left to the browser, so nothing they do is changed.
self.addEventListener('fetch', (event) => {
  const { request } = event;
  if (request.mode !== 'navigate' || request.method !== 'GET') return;
  if (new URL(request.url).origin !== self.location.origin) return;
  event.respondWith(fetch(event.request).catch(() => caches.match(OFFLINE)));
});
