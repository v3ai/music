// Where the music server lives.
// • Opened from the server itself (http://localhost:8484, your Tailscale URL…): same origin.
// • Opened from GitHub Pages: the address you enter once on first launch.

const KEY = 'music.server';
export const ON_PAGES = location.hostname.endsWith('.github.io');

let saved = '';
try { saved = localStorage.getItem(KEY) || ''; } catch {}

export const BASE = saved.replace(/\/+$/, '');
export const needsServer = ON_PAGES && !BASE;
export const apiUrl = (path) => `${BASE}/api${path}`;

export function setServer(url) {
  url = (url || '').trim().replace(/\/+$/, '');
  if (url && !/^https?:\/\//.test(url)) url = 'https://' + url;
  try {
    if (url) localStorage.setItem(KEY, url);
    else localStorage.removeItem(KEY);
  } catch {}
  return url;
}
