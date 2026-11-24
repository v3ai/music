// API client + library state (likes, playlists, saved items, downloads) + on-device offline audio.

const mem = new Map();

async function req(method, path, body) {
  const r = await fetch('/api' + path, {
    method,
    headers: body ? { 'content-type': 'application/json' } : {},
    body: body ? JSON.stringify(body) : undefined,
  });
  if (!r.ok) {
    let msg = `${r.status} ${r.statusText}`;
    try { msg = (await r.json()).detail || msg; } catch {}
    throw new Error(msg);
  }
  return r.json();
}

export const api = {
  /** GET with an optional in-memory cache (ttl ms) so back-navigation is instant. */
  get(path, ttl = 0) {
    if (ttl) {
      const hit = mem.get(path);
      if (hit && hit.t > Date.now()) return hit.p;
      const p = req('GET', path).catch((e) => { mem.delete(path); throw e; });
      mem.set(path, { t: Date.now() + ttl, p });
      return p;
    }
    return req('GET', path);
  },
  post: (p, b = {}) => req('POST', p, b),
  patch: (p, b) => req('PATCH', p, b),
  put: (p, b) => req('PUT', p, b),
  del: (p) => req('DELETE', p),
  invalidate(prefix) {
    for (const k of mem.keys()) if (k.startsWith(prefix)) mem.delete(k);
  },
};

export const slim = (t) => ({
  id: t.id, title: t.title, artists: t.artists || [], album: t.album || null,
  duration: t.duration || null, art: t.art || null, explicit: !!t.explicit,
});

// ---------- event bus ----------

export const bus = new EventTarget();
export const emit = (name, detail) => bus.dispatchEvent(new CustomEvent(name, { detail }));
export const on = (name, fn) => bus.addEventListener(name, (e) => fn(e.detail));

// ---------- library ----------

export const lib = {
  liked: new Set(),
  playlists: [],
  saved: new Map(), // `${kind}:${id}` -> item
  dl: {}, // trackId -> status (server downloads)
  loaded: false,
};

const LIB_KEY = 'music.lib';

function applyLib(d) {
  lib.liked = new Set(d.liked || []);
  lib.playlists = d.playlists || [];
  lib.saved = new Map((d.saved || []).map((s) => [`${s.kind}:${s.id}`, s]));
  lib.dl = d.downloads || {};
  lib.loaded = true;
}

export async function loadLibrary() {
  try {
    const cached = JSON.parse(localStorage.getItem(LIB_KEY) || 'null');
    if (cached && !lib.loaded) { applyLib(cached); emit('lib'); }
  } catch {}
  try {
    const d = await api.get('/library');
    applyLib(d);
    try { localStorage.setItem(LIB_KEY, JSON.stringify(d)); } catch {}
    emit('lib');
    if (Object.values(lib.dl).some((s) => s === 'queued' || s === 'downloading')) pollDownloads();
  } catch (e) {
    console.warn('library offline', e);
  }
}

export const isLiked = (id) => lib.liked.has(id);
export const isSaved = (kind, id) => lib.saved.has(`${kind}:${id}`);
export const dlState = (id) => lib.dl[id];

export async function toggleLike(track, force) {
  const on = force ?? !lib.liked.has(track.id);
  on ? lib.liked.add(track.id) : lib.liked.delete(track.id);
  emit('lib');
  try {
    await api.post('/like', { track: slim(track), on });
    api.invalidate('/liked');
  } catch (e) {
    on ? lib.liked.delete(track.id) : lib.liked.add(track.id);
    emit('lib');
    throw e;
  }
  return on;
}

export async function toggleSave(kind, item, force) {
  const k = `${kind}:${item.id}`;
  const on = force ?? !lib.saved.has(k);
  on ? lib.saved.set(k, { kind, ...item }) : lib.saved.delete(k);
  emit('lib');
  await api.post('/save', { kind, item, on });
  return on;
}

export async function refreshPlaylists() {
  lib.playlists = await api.get('/playlists');
  emit('lib');
}

export async function createPlaylist(name, tracks = []) {
  const p = await api.post('/playlists', { name, tracks: tracks.map(slim) });
  await refreshPlaylists();
  return p;
}

export async function addToPlaylist(pid, tracks) {
  await api.post(`/playlists/${pid}/tracks`, { tracks: tracks.map(slim) });
  api.invalidate(`/playlists/${pid}`);
  await refreshPlaylists();
}

export async function removeFromPlaylist(pid, tid) {
  await api.del(`/playlists/${pid}/tracks/${encodeURIComponent(tid)}`);
  api.invalidate(`/playlists/${pid}`);
  await refreshPlaylists();
}

// ---------- downloads (server library + this device) ----------

let pollTimer = null;
export function pollDownloads() {
  if (pollTimer) return;
  pollTimer = setInterval(async () => {
    try {
      const d = await api.get('/library');
      const before = lib.dl;
      lib.dl = d.downloads || {};
      emit('lib');
      // newly finished on the server -> pull to this device
      for (const [id, s] of Object.entries(lib.dl)) {
        if (s === 'done' && before[id] !== 'done' && wantDevice.has(id)) saveToDevice(id);
      }
      if (!Object.values(lib.dl).some((s) => s === 'queued' || s === 'downloading')) {
        clearInterval(pollTimer);
        pollTimer = null;
        emit('downloads-idle');
      }
    } catch {}
  }, 1500);
}

const AUDIO_CACHE = 'music-audio-v1';
const DEVICE_KEY = 'music.device';
const wantDevice = new Set();
export const device = new Map(); // id -> track meta, audio stored in Cache Storage
try {
  for (const t of JSON.parse(localStorage.getItem(DEVICE_KEY) || '[]')) device.set(t.id, t);
} catch {}
const persistDevice = () => {
  try { localStorage.setItem(DEVICE_KEY, JSON.stringify([...device.values()])); } catch {}
};

export const deviceSupported = () => 'caches' in window && !!navigator.serviceWorker?.controller;
export const onDevice = (id) => device.has(id);

async function saveToDevice(id) {
  wantDevice.delete(id);
  if (!('caches' in window)) return;
  try {
    const url = `/api/stream/${id}`;
    const r = await fetch(url, { cache: 'no-store' });
    if (!r.ok) throw new Error(r.status);
    const blob = await r.blob();
    const c = await caches.open(AUDIO_CACHE);
    await c.put(url, new Response(blob, { headers: { 'content-type': blob.type || 'audio/mp4', 'content-length': String(blob.size) } }));
    const meta = pendingMeta.get(id) || { id };
    if (meta.art) fetch(meta.art, { mode: 'no-cors' }).catch(() => {});
    device.set(id, meta);
    pendingMeta.delete(id);
    persistDevice();
    emit('lib');
  } catch (e) {
    console.warn('device save failed', id, e);
  }
}
const pendingMeta = new Map();

// When the server runs on this same computer, its download folder already *is* local,
// so only keep a second, in-browser copy on other devices (e.g. your phone).
const serverIsLocal = ['localhost', '127.0.0.1', '[::1]'].includes(location.hostname);

export async function download(tracks) {
  tracks = tracks.map(slim);
  for (const t of tracks) {
    if (!lib.dl[t.id] || lib.dl[t.id] === 'error') lib.dl[t.id] = 'queued';
    if ('caches' in window && !serverIsLocal && !device.has(t.id)) {
      wantDevice.add(t.id);
      pendingMeta.set(t.id, t);
    }
  }
  emit('lib');
  await api.post('/downloads', { tracks });
  // already-finished ones can be pulled to the device immediately
  for (const t of tracks) if (lib.dl[t.id] === 'done' && wantDevice.has(t.id)) saveToDevice(t.id);
  pollDownloads();
}

export async function removeDownload(id) {
  delete lib.dl[id];
  if (device.has(id)) {
    device.delete(id);
    persistDevice();
    try { (await caches.open(AUDIO_CACHE)).delete(`/api/stream/${id}`); } catch {}
  }
  emit('lib');
  await api.del(`/downloads/${encodeURIComponent(id)}`);
}

export const isDownloaded = (id) => lib.dl[id] === 'done' || device.has(id);
