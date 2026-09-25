// MAP Trainer service worker.
// Strategy: NETWORK-FIRST for the app page itself (so every deploy reaches
// users on their next visit, instead of the old cache-first behaviour that
// kept serving a stale index.html indefinitely), falling back to the cached
// copy only when offline. Static icons/manifest stay cache-first — they
// rarely change and should load instantly.
// Bump CACHE_NAME only if the list of static files changes.
const CACHE_NAME = 'map-trainer-v2';
const SHELL_FILES = [
  './',
  './index.html',
  './manifest.json',
  './icon-192.png',
  './icon-512.png',
  './icon-maskable-512.png'
];

self.addEventListener('install', (event) => {
  event.waitUntil(
    caches.open(CACHE_NAME)
      .then((cache) => cache.addAll(SHELL_FILES))
      .then(() => self.skipWaiting())
  );
});

self.addEventListener('activate', (event) => {
  event.waitUntil(
    caches.keys().then((keys) =>
      Promise.all(keys.filter((k) => k !== CACHE_NAME).map((k) => caches.delete(k)))
    ).then(() => self.clients.claim())
  );
});

function isAppPage(request) {
  if (request.mode === 'navigate') return true;
  const url = new URL(request.url);
  return url.origin === self.location.origin &&
    (url.pathname.endsWith('/') || url.pathname.endsWith('.html'));
}

self.addEventListener('fetch', (event) => {
  const req = event.request;
  if (req.method !== 'GET') return;
  // Never intercept cross-origin calls (Supabase API, CDN) — let the
  // browser handle them normally.
  if (new URL(req.url).origin !== self.location.origin) return;

  if (isAppPage(req)) {
    event.respondWith(
      fetch(req)
        .then((response) => {
          if (response && response.status === 200) {
            const copy = response.clone();
            caches.open(CACHE_NAME).then((cache) => cache.put('./index.html', copy));
          }
          return response;
        })
        .catch(() => caches.match('./index.html'))
    );
    return;
  }

  event.respondWith(
    caches.match(req).then((cached) => cached || fetch(req).then((response) => {
      if (response && response.status === 200) {
        const copy = response.clone();
        caches.open(CACHE_NAME).then((cache) => cache.put(req, copy));
      }
      return response;
    }))
  );
});
