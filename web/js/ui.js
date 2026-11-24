// Shared UI helpers: icons, formatting, components, menus, sheets, toasts, dialogs.
import { apiUrl } from './config.js';

const S = (body, { fill = false, w = 2 } = {}) =>
  `<svg viewBox="0 0 24 24" aria-hidden="true" ${fill ? 'fill="currentColor" stroke="none"' : `fill="none" stroke="currentColor" stroke-width="${w}" stroke-linecap="round" stroke-linejoin="round"`}>${body}</svg>`;

export const icon = {
  play: S('<path d="M7 4.8v14.4a1 1 0 0 0 1.53.85l11.4-7.2a1 1 0 0 0 0-1.7L8.53 3.95A1 1 0 0 0 7 4.8z"/>', { fill: true }),
  pause: S('<rect x="5.5" y="4" width="4.5" height="16" rx="1.2"/><rect x="14" y="4" width="4.5" height="16" rx="1.2"/>', { fill: true }),
  next: S('<path d="M5 5.4v13.2a1 1 0 0 0 1.55.83L16 13.1V18a1 1 0 0 0 2 0V6a1 1 0 0 0-2 0v4.9L6.55 4.57A1 1 0 0 0 5 5.4z"/>', { fill: true }),
  prev: S('<path d="M19 5.4v13.2a1 1 0 0 1-1.55.83L8 13.1V18a1 1 0 0 1-2 0V6a1 1 0 0 1 2 0v4.9l9.45-6.33A1 1 0 0 1 19 5.4z"/>', { fill: true }),
  shuffle: S('<path d="M16 3h5v5M4 20 21 3M21 16v5h-5M15 15l6 6M4 4l5 5"/>'),
  repeat: S('<path d="m17 2 4 4-4 4"/><path d="M3 11V10a4 4 0 0 1 4-4h14"/><path d="m7 22-4-4 4-4"/><path d="M21 13v1a4 4 0 0 1-4 4H3"/>'),
  repeat1: S('<path d="m17 2 4 4-4 4"/><path d="M3 11V10a4 4 0 0 1 4-4h14"/><path d="m7 22-4-4 4-4"/><path d="M21 13v1a4 4 0 0 1-4 4H3"/><path d="M11 10.5 12.5 9.5V15" stroke-width="1.8"/>'),
  heart: S('<path d="M20.8 4.6a5.5 5.5 0 0 0-7.8 0L12 5.7l-1-1.1a5.5 5.5 0 0 0-7.8 7.8l1 1.1L12 21.2l7.8-7.7 1-1.1a5.5 5.5 0 0 0 0-7.8z"/>'),
  heartFill: S('<path d="M20.8 4.6a5.5 5.5 0 0 0-7.8 0L12 5.7l-1-1.1a5.5 5.5 0 0 0-7.8 7.8l1 1.1L12 21.2l7.8-7.7 1-1.1a5.5 5.5 0 0 0 0-7.8z"/>', { fill: true }),
  download: S('<circle cx="12" cy="12" r="9.5"/><path d="M12 7.5v8.5M8.5 12.5 12 16l3.5-3.5"/>', { w: 1.8 }),
  downloaded: `<svg viewBox="0 0 24 24" aria-hidden="true"><circle cx="12" cy="12" r="10.5" fill="currentColor"/><path d="M12 7v8.5M8.5 12 12 15.5 15.5 12" fill="none" style="stroke:var(--bg)" stroke-width="2.2" stroke-linecap="round" stroke-linejoin="round"/></svg>`,
  downloading: `<svg viewBox="0 0 24 24" aria-hidden="true" class="spin"><circle cx="12" cy="12" r="9.5" fill="none" stroke="currentColor" stroke-opacity=".25" stroke-width="2"/><path d="M12 2.5a9.5 9.5 0 0 1 9.5 9.5" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round"/></svg>`,
  search: S('<circle cx="11" cy="11" r="7"/><path d="m20.5 20.5-4.5-4.5"/>', { w: 2.2 }),
  home: S('<path d="M3.5 10.2 12 3.5l8.5 6.7V20a1 1 0 0 1-1 1H15v-6.5H9V21H4.5a1 1 0 0 1-1-1z"/>'),
  homeFill: S('<path d="M3.5 10.2 12 3.5l8.5 6.7V20a1 1 0 0 1-1 1H15v-6.5H9V21H4.5a1 1 0 0 1-1-1z" fill="currentColor"/>'),
  library: S('<path d="M4.5 3.5v17M9.5 3.5v17M14 4.5l5.5 15.5"/>', { w: 2.2 }),
  plus: S('<path d="M12 5v14M5 12h14"/>'),
  more: S('<circle cx="5" cy="12" r="1.8"/><circle cx="12" cy="12" r="1.8"/><circle cx="19" cy="12" r="1.8"/>', { fill: true }),
  queue: S('<path d="M3 6h14M3 12h14M3 18h8M15 15.5v6l5-3z"/>'),
  lyrics: S('<path d="M12 2.5a3 3 0 0 0-3 3V12a3 3 0 0 0 6 0V5.5a3 3 0 0 0-3-3z"/><path d="M18.5 10.5V12a6.5 6.5 0 0 1-13 0v-1.5M12 18.5v3"/>'),
  volume: S('<path d="M11 5 6 9H3v6h3l5 4z" fill="currentColor"/><path d="M15.5 8.5a5 5 0 0 1 0 7M18.5 5.5a9.2 9.2 0 0 1 0 13"/>'),
  volumeLow: S('<path d="M11 5 6 9H3v6h3l5 4z" fill="currentColor"/><path d="M15.5 8.5a5 5 0 0 1 0 7"/>'),
  mute: S('<path d="M11 5 6 9H3v6h3l5 4z" fill="currentColor"/><path d="m16 9 6 6M22 9l-6 6"/>'),
  down: S('<path d="m6 9 6 6 6-6"/>', { w: 2.2 }),
  back: S('<path d="m15 18-6-6 6-6"/>', { w: 2.2 }),
  fwd: S('<path d="m9 18 6-6-6-6"/>', { w: 2.2 }),
  check: S('<path d="M20 6 9 17l-5-5"/>', { w: 2.4 }),
  note: S('<path d="M9 18V5.5l11-2V16"/><circle cx="6.5" cy="18" r="2.5"/><circle cx="17.5" cy="16" r="2.5"/>', { w: 1.6 }),
  radio: S('<circle cx="12" cy="12" r="2"/><path d="M16.2 7.8a6 6 0 0 1 0 8.4M7.8 16.2a6 6 0 0 1 0-8.4M19.1 4.9a10 10 0 0 1 0 14.2M4.9 19.1a10 10 0 0 1 0-14.2"/>'),
  trash: S('<path d="M3.5 6h17M8.5 6V4a1 1 0 0 1 1-1h5a1 1 0 0 1 1 1v2M18.5 6l-.8 13.1a2 2 0 0 1-2 1.9H8.3a2 2 0 0 1-2-1.9L5.5 6"/>'),
  edit: S('<path d="M12 20h9M16.5 3.5a2.1 2.1 0 0 1 3 3L7 19l-4 1 1-4z"/>'),
  user: S('<circle cx="12" cy="8" r="4"/><path d="M4 21a8 8 0 0 1 16 0"/>'),
  disc: S('<circle cx="12" cy="12" r="9.5"/><circle cx="12" cy="12" r="2.5"/>'),
  link: S('<path d="M10 13a5 5 0 0 0 7.5.5l3-3a5 5 0 0 0-7-7l-1.7 1.7"/><path d="M14 11a5 5 0 0 0-7.5-.5l-3 3a5 5 0 0 0 7 7l1.7-1.7"/>'),
  x: S('<path d="M18 6 6 18M6 6l12 12"/>', { w: 2.2 }),
  clock: S('<circle cx="12" cy="12" r="9"/><path d="M12 7v5l3 2"/>', { w: 1.6 }),
  expand: S('<path d="M15 3h6v6M9 21H3v-6M21 3l-7 7M3 21l7-7"/>'),
  next1: S('<path d="M5 12h14M13 6l6 6-6 6"/>'),
  addQueue: S('<path d="M3 6h12M3 12h12M3 18h7M18 13v8M14 17h8"/>'),
  addList: S('<path d="M3 6h12M3 12h12M3 18h7M18 13v8M14 17h8"/>'),
  save: S('<circle cx="12" cy="12" r="9.5"/><path d="M12 8v8M8 12h8"/>', { w: 1.8 }),
  saved: `<svg viewBox="0 0 24 24" aria-hidden="true"><circle cx="12" cy="12" r="10.5" fill="currentColor"/><path d="m7.5 12.3 3 3 6-6.3" fill="none" style="stroke:var(--bg)" stroke-width="2.2" stroke-linecap="round" stroke-linejoin="round"/></svg>`,
  arrowDown: S('<path d="M12 4v15M6 13l6 6 6-6"/>', { w: 2.2 }),
  settings: S('<circle cx="12" cy="12" r="3"/><path d="M19.4 15a1.65 1.65 0 0 0 .33 1.82l.06.06a2 2 0 1 1-2.83 2.83l-.06-.06a1.65 1.65 0 0 0-1.82-.33 1.65 1.65 0 0 0-1 1.51V21a2 2 0 1 1-4 0v-.09A1.65 1.65 0 0 0 9 19.4a1.65 1.65 0 0 0-1.82.33l-.06.06a2 2 0 1 1-2.83-2.83l.06-.06A1.65 1.65 0 0 0 4.68 15a1.65 1.65 0 0 0-1.51-1H3a2 2 0 1 1 0-4h.09A1.65 1.65 0 0 0 4.6 9a1.65 1.65 0 0 0-.33-1.82l-.06-.06a2 2 0 1 1 2.83-2.83l.06.06A1.65 1.65 0 0 0 9 4.68a1.65 1.65 0 0 0 1-1.51V3a2 2 0 1 1 4 0v.09a1.65 1.65 0 0 0 1 1.51 1.65 1.65 0 0 0 1.82-.33l.06-.06a2 2 0 1 1 2.83 2.83l-.06.06A1.65 1.65 0 0 0 19.4 9a1.65 1.65 0 0 0 1.51 1H21a2 2 0 1 1 0 4h-.09a1.65 1.65 0 0 0-1.51 1z"/>', { w: 1.8 }),
  phone: S('<rect x="6" y="2.5" width="12" height="19" rx="2.5"/><path d="M11 18h2"/>'),
  bars: `<span class="eq" aria-hidden="true"><i></i><i></i><i></i></span>`,
};

export const esc = (s) =>
  String(s ?? '').replace(/[&<>"']/g, (c) => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;' })[c]);

export function fmtTime(s) {
  if (!isFinite(s) || s < 0) s = 0;
  s = Math.floor(s);
  const h = Math.floor(s / 3600), m = Math.floor((s % 3600) / 60), sec = String(s % 60).padStart(2, '0');
  return h ? `${h}:${String(m).padStart(2, '0')}:${sec}` : `${m}:${sec}`;
}

export function fmtLong(s) {
  if (!s) return '';
  const h = Math.floor(s / 3600), m = Math.round((s % 3600) / 60);
  return h ? `${h} hr ${m} min` : `${m} min`;
}

const dpr = Math.min(window.devicePixelRatio || 1, 2);

// when an image can't be loaded at all, show a neutral placeholder
window.artFail = (el) => {
  el.onerror = null;
  el.src = window.ART_PH;
};

// shown when album art fails to load
window.ART_PH = 'data:image/svg+xml,' + encodeURIComponent(
  '<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 24 24"><rect width="24" height="24" fill="#242424"/>' +
  '<g fill="none" stroke="#6f6f6f" stroke-width=".8" stroke-linecap="round" stroke-linejoin="round" transform="translate(6 6) scale(.5)">' +
  '<path d="M9 18V5.5l11-2V16"/><circle cx="6.5" cy="18" r="2.5"/><circle cx="17.5" cy="16" r="2.5"/></g></svg>');

const SIZES = [96, 160, 240, 360, 544, 800, 1200];

/**
 * Artwork URL at (at least) the size we display. Images are loaded through the music
 * server, which caches them on disk — loading dozens of covers straight from Google
 * gets rate-limited and leaves blank squares. Sizes snap to a few steps so each cover
 * is fetched in as few variants as possible.
 */
export function img(url, px = 120) {
  if (!url) return '';
  if (url.startsWith('data:') || url.startsWith('/api/')) return url;
  const n = SIZES.find((s) => s >= px * dpr) || 1200;
  if (/googleusercontent\.com|ggpht\.com/.test(url)) {
    url = url.replace(/=[ws]\d+[^/=]*$/, '') + `=w${n}-h${n}-l90-rj`;
  }
  return apiUrl(`/img?u=${encodeURIComponent(url)}`);
}

export const artistsText = (t) => (t.artists || []).map((a) => a.name).join(', ');

export function artistLinks(t) {
  const a = t.artists || [];
  if (!a.length) return '';
  return a
    .map((x) => (x.id ? `<a href="#/artist/${esc(x.id)}" data-stop>${esc(x.name)}</a>` : esc(x.name)))
    .join(', ');
}

export function art(url, px, cls = '', round = false) {
  return url
    ? `<img class="art ${cls}${round ? ' round' : ''}" src="${esc(img(url, px))}" loading="lazy" decoding="async" alt="" onerror="artFail(this)">`
    : `<div class="art ph ${cls}${round ? ' round' : ''}">${icon.note}</div>`;
}

// ---------- list registry: lets markup refer to arrays of tracks ----------

const lists = new Map();
let listSeq = 0;
export function reg(tracks, meta = {}) {
  const key = 'L' + ++listSeq;
  lists.set(key, { tracks, ...meta });
  if (lists.size > 200) lists.delete(lists.keys().next().value);
  return key;
}
export const getList = (k) => lists.get(k);
export function* allTracks() {
  for (const l of lists.values()) yield* l.tracks;
}

// ---------- components ----------

/**
 * Track row. `opts.num` shows index numbers (albums), otherwise thumbnails.
 */
export function trackRow(t, i, key, opts = {}, state = {}) {
  const playing = state.currentId === t.id;
  const dl = state.dl?.(t.id);
  const numHtml = `<div class="tr-num">${playing ? icon.bars : `<span>${i + 1}</span>`}<button class="tr-numplay" tabindex="-1">${icon.play}</button></div>`;
  const artHtml = `<div class="tr-art">${art(t.art, 48)}${playing && !opts.num ? `<div class="tr-art-eq">${icon.bars}</div>` : ''}</div>`;
  const lead = opts.num ? numHtml + (opts.art ? artHtml : '') : artHtml;
  const sig = `${playing}|${!!state.liked?.(t.id)}|${dl || (state.device?.(t.id) ? 'done' : '')}`;
  return `<div class="tr${playing ? ' playing' : ''}" data-list="${key}" data-i="${i}" data-id="${esc(t.id)}" data-sig="${sig}" role="button" tabindex="0">
    ${lead}
    <div class="tr-main">
      <div class="tr-title">${esc(t.title)}</div>
      <div class="tr-sub">${dl === 'done' || state.device?.(t.id) ? `<span class="tr-dl">${icon.downloaded}</span>` : dl === 'downloading' || dl === 'queued' ? `<span class="tr-dl">${icon.downloading}</span>` : ''}${t.explicit ? '<span class="badge-e">E</span>' : ''}${opts.noArtist ? '' : artistLinks(t)}</div>
    </div>
    ${opts.album !== false && t.album?.name ? `<div class="tr-album">${t.album.id ? `<a href="#/album/${esc(t.album.id)}" data-stop>${esc(t.album.name)}</a>` : esc(t.album.name)}</div>` : '<div class="tr-album"></div>'}
    <button class="tr-like ${state.liked?.(t.id) ? 'on' : ''}" data-like aria-label="Like">${state.liked?.(t.id) ? icon.heartFill : icon.heart}</button>
    <div class="tr-dur">${t.duration ? fmtTime(t.duration) : ''}</div>
    <button class="tr-more" data-menu aria-label="More">${icon.more}</button>
  </div>`;
}

export function card(item, opts = {}) {
  const k = item.kind;
  let href = '', title = '', sub = '', round = false, playAttr = '';
  if (k === 'album') {
    href = `#/album/${item.id}`;
    title = item.title;
    sub = [item.year, item.type && item.type !== 'Album' ? item.type : null, (item.artists || []).map((a) => a.name).join(', ')]
      .filter(Boolean).join(' · ');
    playAttr = `data-play-album="${esc(item.id)}"`;
  } else if (k === 'artist') {
    href = `#/artist/${item.id}`;
    title = item.name || item.title;
    sub = 'Artist';
    round = true;
    playAttr = `data-play-artist="${esc(item.id)}"`;
  } else if (k === 'playlist') {
    href = `#/yt/${item.id}`;
    title = item.title;
    sub = item.author ? `${item.author}` : 'Playlist';
    playAttr = `data-play-yt="${esc(item.id)}"`;
  } else if (k === 'local') {
    href = `#/playlist/${item.id}`;
    title = item.name;
    sub = `${item.count} song${item.count === 1 ? '' : 's'}`;
    playAttr = `data-play-local="${esc(item.id)}"`;
  } else if (k === 'track') {
    title = item.title;
    sub = artistsText(item);
  }
  const cover = k === 'local' ? mosaic(item.covers, 200) : art(item.art, 200, '', round);
  const attrs = k === 'track' ? `data-list="${opts.list}" data-i="${opts.i}" data-id="${esc(item.id)}"` : `data-href="${href}"`;
  return `<div class="card${round ? ' card-round' : ''}" ${attrs} role="button" tabindex="0">
    <div class="card-art">${cover}<button class="card-play" ${k === 'track' ? 'data-card-track' : playAttr} aria-label="Play">${icon.play}</button></div>
    <div class="card-title">${esc(title)}</div>
    <div class="card-sub">${esc(sub)}</div>
  </div>`;
}

export function mosaic(covers = [], px = 200, cls = '') {
  if (!covers.length) return `<div class="art ph ${cls}">${icon.note}</div>`;
  if (covers.length < 4) return art(covers[0], px, cls);
  return `<div class="art mosaic ${cls}">${covers.slice(0, 4).map((c) => `<img src="${esc(img(c, px / 2))}" loading="lazy" alt="">`).join('')}</div>`;
}

export function shelf(title, items, opts = {}) {
  if (!items?.length) return '';
  const key = opts.trackList || reg(items.filter((x) => x.kind === 'track'));
  let ti = 0;
  return `<section class="shelf">
    <div class="shelf-head"><h2>${opts.href ? `<a href="${opts.href}">${esc(title)}</a>` : esc(title)}</h2>${opts.href ? `<a class="shelf-more" href="${opts.href}">Show all</a>` : ''}</div>
    <div class="shelf-row">${items.map((x) => card(x, x.kind === 'track' ? { list: key, i: ti++ } : {})).join('')}</div>
  </section>`;
}

export function skeleton(kind = 'page') {
  if (kind === 'list') return `<div class="sk-list">${'<div class="sk-row"><div class="sk sk-art"></div><div class="sk-lines"><div class="sk sk-l1"></div><div class="sk sk-l2"></div></div></div>'.repeat(8)}</div>`;
  return `<div class="sk-page"><div class="sk-hero"><div class="sk sk-cover"></div><div class="sk-lines"><div class="sk sk-l2"></div><div class="sk sk-h"></div><div class="sk sk-l1"></div></div></div>${skeleton('list')}</div>`;
}

export function errorView(e, retry = true) {
  return `<div class="empty"><div class="empty-icon">${icon.note}</div><h2>Couldn't load this</h2><p>${esc(e?.message || e)}</p>${retry ? '<button class="btn" data-action="reload">Try again</button>' : ''}</div>`;
}

// ---------- toast ----------

let toastTimer;
export function toast(msg) {
  const el = document.getElementById('toast');
  el.textContent = msg;
  el.classList.add('show');
  clearTimeout(toastTimer);
  toastTimer = setTimeout(() => el.classList.remove('show'), 2400);
}

// ---------- menus (popover on desktop, bottom sheet on mobile) ----------

export const isMobile = () => matchMedia('(max-width: 760px)').matches;

let openMenuEl = null;
export function closeMenu() {
  if (!openMenuEl) return;
  const el = openMenuEl;
  openMenuEl = null;
  el.classList.remove('open');
  setTimeout(() => el.remove(), 200);
}

/**
 * items: [{icon, label, run, sub?: items}] or '-' separators.
 * header: optional HTML shown on mobile sheets.
 */
export function openMenu(anchor, items, header = '') {
  closeMenu();
  const mobile = isMobile();
  const el = document.createElement('div');
  el.className = mobile ? 'sheet-wrap' : 'menu-wrap';
  const list = items
    .filter(Boolean)
    .map((it, i) => (it === '-' ? '<div class="menu-sep"></div>' : `<button class="menu-item" data-mi="${i}">${it.icon || ''}<span>${esc(it.label)}</span>${it.sub ? `<span class="menu-arrow">${icon.fwd}</span>` : ''}</button>`))
    .join('');
  el.innerHTML = mobile
    ? `<div class="sheet-bg"></div><div class="sheet">${header ? `<div class="sheet-head">${header}</div>` : '<div class="sheet-grab"></div>'}<div class="sheet-list">${list}</div></div>`
    : `<div class="menu">${list}</div>`;
  document.body.appendChild(el);
  const clean = items.filter(Boolean);
  el.addEventListener('click', (e) => {
    const b = e.target.closest('[data-mi]');
    if (!b) {
      if (e.target.classList.contains('sheet-bg')) closeMenu();
      return;
    }
    const it = clean[+b.dataset.mi];
    if (it.sub) {
      const sub = typeof it.sub === 'function' ? it.sub() : it.sub;
      openMenu(anchor, sub, header);
      return;
    }
    closeMenu();
    it.run?.();
  });
  if (!mobile) {
    const m = el.querySelector('.menu');
    const r = anchor?.getBoundingClientRect?.() || { left: innerWidth / 2, right: innerWidth / 2, top: innerHeight / 2, bottom: innerHeight / 2 };
    m.style.visibility = 'hidden';
    requestAnimationFrame(() => {
      const mw = m.offsetWidth, mh = m.offsetHeight;
      let left = r.right - mw;
      if (left < 8) left = Math.min(r.left, innerWidth - mw - 8);
      let top = r.bottom + 6;
      if (top + mh > innerHeight - 8) top = Math.max(8, r.top - mh - 6);
      m.style.left = left + 'px';
      m.style.top = top + 'px';
      m.style.visibility = '';
    });
  }
  requestAnimationFrame(() => el.classList.add('open'));
  openMenuEl = el;
}

document.addEventListener('pointerdown', (e) => {
  if (openMenuEl && !openMenuEl.classList.contains('sheet-wrap') && !e.target.closest('.menu')) closeMenu();
}, true);
window.addEventListener('hashchange', closeMenu);
window.addEventListener('keydown', (e) => e.key === 'Escape' && closeMenu());

// ---------- dialog ----------

export function prompt({ title, value = '', placeholder = '', ok = 'Save' }) {
  return new Promise((resolve) => {
    const el = document.createElement('div');
    el.className = 'dialog-wrap';
    el.innerHTML = `<form class="dialog"><h3>${esc(title)}</h3><input class="input" value="${esc(value)}" placeholder="${esc(placeholder)}" maxlength="100"><div class="dialog-actions"><button type="button" class="btn btn-ghost" data-cancel>Cancel</button><button class="btn">${esc(ok)}</button></div></form>`;
    document.body.appendChild(el);
    const input = el.querySelector('input');
    requestAnimationFrame(() => { el.classList.add('open'); input.focus(); input.select(); });
    const done = (v) => { el.classList.remove('open'); setTimeout(() => el.remove(), 200); resolve(v); };
    el.querySelector('form').onsubmit = (e) => { e.preventDefault(); done(input.value.trim()); };
    el.querySelector('[data-cancel]').onclick = () => done(null);
    el.addEventListener('click', (e) => e.target === el && done(null));
    el.addEventListener('keydown', (e) => e.key === 'Escape' && done(null));
  });
}

export function confirmDialog(title, msg, ok = 'Delete') {
  return new Promise((resolve) => {
    const el = document.createElement('div');
    el.className = 'dialog-wrap';
    el.innerHTML = `<div class="dialog"><h3>${esc(title)}</h3><p>${esc(msg)}</p><div class="dialog-actions"><button class="btn btn-ghost" data-cancel>Cancel</button><button class="btn" data-ok>${esc(ok)}</button></div></div>`;
    document.body.appendChild(el);
    requestAnimationFrame(() => el.classList.add('open'));
    const done = (v) => { el.classList.remove('open'); setTimeout(() => el.remove(), 200); resolve(v); };
    el.querySelector('[data-cancel]').onclick = () => done(false);
    el.querySelector('[data-ok]').onclick = () => done(true);
    el.addEventListener('click', (e) => e.target === el && done(false));
  });
}
