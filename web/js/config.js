// Where the music server lives. Found automatically — no setup screen:
// • Opened from the server itself (http://localhost:8484, a Tailscale URL…): same origin.
// • Opened from GitHub Pages: the first of these that answers —
//     1. an address set in Settings (optional),
//     2. DEFAULT_SERVER, filled in at deploy time from the repo variable MUSIC_SERVER_URL,
//     3. the server on this same computer (desktop only).

const KEY = 'music.server';
const LAST = 'music.server.last';
const DEFAULT_SERVER = ''; // replaced by .github/workflows/pages.yml
export const ON_PAGES = location.hostname.endsWith('.github.io');

const read = (k) => { try { return localStorage.getItem(k) || ''; } catch { return ''; } };
const write = (k, v) => { try { v ? localStorage.setItem(k, v) : localStorage.removeItem(k); } catch {} };
const clean = (u) => {
  u = (u || '').trim().replace(/\/+$/, '');
  return u && !/^https?:\/\//.test(u) ? `https://${u}` : u;
};

export let BASE = ON_PAGES ? read(LAST) : clean(read(KEY));
export let connected = !ON_PAGES;
export const apiUrl = (path) => `${BASE}/api${path}`;
export const manualServer = () => read(KEY);

function candidates() {
  const c = [clean(read(KEY)), clean(DEFAULT_SERVER)];
  // only a desktop can be running the server itself; probing localhost from a phone is pointless
  if (!matchMedia('(pointer: coarse)').matches) c.push('http://localhost:8484');
  return [...new Set(c.filter(Boolean))];
}

async function probe(url, ms = 3000) {
  const ctl = new AbortController();
  const t = setTimeout(() => ctl.abort(), ms);
  try {
    const r = await fetch(`${url}/api/ping`, { signal: ctl.signal, cache: 'no-store' });
    return r.ok;
  } catch {
    return false;
  } finally {
    clearTimeout(t);
  }
}

/** Find a reachable server (GitHub Pages only). Resolves to true when connected. */
export async function findServer() {
  if (!ON_PAGES) return true;
  const list = candidates();
  // remembered one first, so normal start-up is a single quick request
  const last = read(LAST);
  if (last && list.includes(last) && (await probe(last, 2500))) {
    BASE = last;
    connected = true;
    return true;
  }
  const results = await Promise.all(list.map((u) => probe(u)));
  const i = results.indexOf(true);
  connected = i >= 0;
  if (connected) {
    BASE = list[i];
    write(LAST, BASE);
  }
  return connected;
}

/** Optional manual address from Settings ('' to go back to automatic). */
export function setServer(url) {
  url = clean(url);
  write(KEY, url);
  write(LAST, url);
  return url;
}
