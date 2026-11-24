// Service worker: instant app-shell loads, offline library data, cached album art,
// and playback of songs downloaded to this device (with HTTP Range support).

const VERSION = 'v1';
const SHELL = `music-shell-${VERSION}`;
const API = 'music-api-v1';
const ART = 'music-art-v1';
const AUDIO = 'music-audio-v1'; // written by the page when you download a song
const KEEP = [SHELL, API, ART, AUDIO];

// relative to this file, so it works both at / (served by the music server) and at /music/ (GitHub Pages)
const ASSETS = [
  './', 'css/app.css', 'js/main.js', 'js/ui.js', 'js/state.js', 'js/player.js', 'js/views.js', 'js/config.js',
  'manifest.webmanifest', 'icons/icon.svg', 'icons/icon-192.png', 'icons/apple-touch-icon.png',
];
const ART_HOSTS = /googleusercontent\.com|ggpht\.com|ytimg\.com/;

self.addEventListener('install', (e) => {
  e.waitUntil(caches.open(SHELL).then((c) => c.addAll(ASSETS)).then(() => self.skipWaiting()));
});

self.addEventListener('activate', (e) => {
  e.waitUntil((async () => {
    for (const k of await caches.keys()) if (!KEEP.includes(k)) await caches.delete(k);
    await self.clients.claim();
  })());
});

self.addEventListener('fetch', (e) => {
  const req = e.request;
  if (req.method !== 'GET') return;
  const url = new URL(req.url);

  // the music server's API (same origin, or another origin when the app runs on GitHub Pages)
  if (url.pathname.startsWith('/api/') && !ART_HOSTS.test(url.hostname)) {
    if (url.pathname.startsWith('/api/stream/')) return e.respondWith(stream(req, url));
    if (url.pathname === '/api/img' || url.pathname.startsWith('/api/cover/')) return e.respondWith(artwork(req));
    if (url.pathname.startsWith('/api/')) return e.respondWith(networkFirst(req));
  }

  if (url.origin === location.origin) {
    if (req.mode === 'navigate') return e.respondWith(staleWhileRevalidate(new Request('./'), SHELL));
    return e.respondWith(staleWhileRevalidate(req, SHELL));
  }

  if (req.destination === 'image' || ART_HOSTS.test(url.hostname)) {
    return e.respondWith(artwork(req));
  }
});

async function stream(req, url) {
  const cache = await caches.open(AUDIO);
  const hit = await cache.match(new URL(url.pathname, location.origin).href);
  if (!hit) return fetch(req);
  const blob = await hit.blob();
  const type = hit.headers.get('content-type') || 'audio/mp4';
  const size = blob.size;
  const range = req.headers.get('range');
  if (!range) {
    return new Response(blob, { status: 200, headers: { 'content-type': type, 'content-length': String(size), 'accept-ranges': 'bytes' } });
  }
  const m = /bytes=(\d*)-(\d*)/.exec(range) || [];
  let start = m[1] ? +m[1] : 0;
  let end = m[2] ? +m[2] : size - 1;
  if (!m[1] && m[2]) { start = Math.max(0, size - +m[2]); end = size - 1; }
  end = Math.min(end, size - 1);
  if (start > end || start >= size) {
    return new Response(null, { status: 416, headers: { 'content-range': `bytes */${size}` } });
  }
  return new Response(blob.slice(start, end + 1), {
    status: 206,
    headers: {
      'content-type': type, 'accept-ranges': 'bytes',
      'content-range': `bytes ${start}-${end}/${size}`, 'content-length': String(end - start + 1),
    },
  });
}

async function networkFirst(req) {
  const cache = await caches.open(API);
  try {
    const res = await fetch(req);
    if (res.ok) cache.put(req, res.clone()).then(() => trim(cache, 400));
    return res;
  } catch (err) {
    const hit = await cache.match(req);
    if (hit) return hit;
    return new Response(JSON.stringify({ detail: 'You’re offline' }), { status: 503, headers: { 'content-type': 'application/json' } });
  }
}

async function staleWhileRevalidate(req, name) {
  const cache = await caches.open(name);
  const hit = await cache.match(req, { ignoreSearch: true });
  const net = fetch(req).then((res) => {
    if (res.ok) cache.put(req, res.clone());
    return res;
  }).catch(() => hit);
  return hit || net;
}

// Album art comes in many sizes (same image, different URL suffix). Keep a size-less
// copy too, so offline we can show *some* size of the cover instead of nothing.
function artKey(u) {
  let url = new URL(u);
  if (url.pathname === '/api/img' && url.searchParams.get('u')) url = new URL(url.searchParams.get('u'));
  if (/googleusercontent\.com|ggpht\.com/.test(url.hostname)) return `${url.origin}${url.pathname.replace(/=[^/]*$/, '')}=any`;
  const m = /^\/vi\/([\w-]{11})\//.exec(url.pathname);
  if (m) return `https://i.ytimg.com/vi/${m[1]}/any`;
  return null;
}

async function artwork(req) {
  const cache = await caches.open(ART);
  const hit = await cache.match(req);
  if (hit) return hit;
  const key = artKey(req.url);
  try {
    const res = await fetch(req);
    if (res.ok || res.type === 'opaque') {
      await cache.put(req, res.clone());
      if (key) await cache.put(key, res.clone());
      trim(cache, 1500);
    }
    return res;
  } catch {
    return (key && (await cache.match(key))) || Response.error();
  }
}

const trimming = new Set();
async function trim(cache, max) {
  if (trimming.has(cache)) return;
  trimming.add(cache);
  try {
    const keys = await cache.keys();
    for (const k of keys.slice(0, Math.max(0, keys.length - max))) await cache.delete(k);
  } finally {
    trimming.delete(cache);
  }
}

async function cacheFirst(req, name, max = 0) {
  const cache = await caches.open(name);
  const hit = await cache.match(req);
  if (hit) return hit;
  try {
    const res = await fetch(req);
    if (res.ok || res.type === 'opaque') {
      await cache.put(req, res.clone());
      if (max) trim(cache, max);
    }
    return res;
  } catch {
    return hit || Response.error();
  }
}
