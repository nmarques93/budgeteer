// Minimal app-shell cache. Budgeteer is LiveView-first — almost everything
// is dynamic, server-rendered content pushed over a WebSocket, which this
// service worker never sees or touches (fetch/install events don't fire for
// WS traffic). All this does is let the static shell (css/js/logo/manifest)
// load instantly and work offline; it deliberately does not cache or
// intercept page HTML, so users always see live data, never a stale page.
const CACHE_NAME = "budgeteer-shell-v1"
const SHELL_PATHS = ["/assets/css/app.css", "/assets/js/app.js", "/images/logo.svg", "/manifest.json"]

self.addEventListener("install", event => {
  event.waitUntil(caches.open(CACHE_NAME).then(cache => cache.addAll(SHELL_PATHS)))
  self.skipWaiting()
})

self.addEventListener("activate", event => {
  event.waitUntil(
    caches.keys().then(names => Promise.all(names.filter(name => name !== CACHE_NAME).map(name => caches.delete(name))))
  )
  self.clients.claim()
})

self.addEventListener("fetch", event => {
  const url = new URL(event.request.url)
  const isShellAsset = event.request.method === "GET" && SHELL_PATHS.includes(url.pathname)

  if (!isShellAsset) return

  event.respondWith(
    caches.match(event.request).then(cached => cached || fetch(event.request))
  )
})
