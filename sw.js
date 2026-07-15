const CACHE = 'kube-stock-v1';

self.addEventListener('install', () => self.skipWaiting());
self.addEventListener('activate', e => e.waitUntil(clients.claim()));

self.addEventListener('fetch', e => {
  if (e.request.method !== 'GET') return;

  const url = new URL(e.request.url);

  // Ne pas intercepter les CDN externes — le navigateur gère son propre cache HTTP
  if (url.origin !== self.location.origin) return;

  // Network-first pour index.html et version.json (garantit les mises à jour)
  if (e.request.mode === 'navigate' || url.pathname === '/version.json') {
    e.respondWith(
      fetch(e.request)
        .then(res => {
          caches.open(CACHE).then(c => c.put(e.request, res.clone()));
          return res;
        })
        .catch(() => caches.match(e.request))
    );
    return;
  }

  // Cache-first pour les autres assets same-origin (icônes, manifest…)
  e.respondWith(
    caches.match(e.request).then(cached => {
      if (cached) return cached;
      return fetch(e.request).then(res => {
        caches.open(CACHE).then(c => c.put(e.request, res.clone()));
        return res;
      });
    })
  );
});
