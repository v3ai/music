import { api, lib, on, loadLibrary, isLiked, dlState, onDevice, toggleLike, download, removeDownload, addToPlaylist, removeFromPlaylist, isDownloaded, slim } from './state.js';
import { player } from './player.js';
import {
  icon, esc, art, img, fmtTime, artistLinks, artistsText, getList, reg, trackRow, toast, openMenu, closeMenu, isMobile, mosaic,
  allTracks,
} from './ui.js';
import * as views from './views.js';
import { ON_PAGES, findServer, connected } from './config.js';

const $ = (s, r = document) => r.querySelector(s);
const plural = (n, w) => `${n} ${w}${n === 1 ? '' : 's'}`;
const view = $('#view');
const main = $('#main');

// static icons in index.html
for (const el of document.querySelectorAll('i[data-icon]')) el.outerHTML = icon[el.dataset.icon] || '';

// ---------- helpers used by views ----------

export const rowState = () => ({
  currentId: player.current?.id,
  liked: isLiked,
  dl: dlState,
  device: onDevice,
});

export function setTitle(t) {
  $('#topbar-title').textContent = t || '';
  document.title = t ? `${t} · music` : 'music';
}

export function addToPlaylistItems(tracks) {
  return [
    { icon: icon.plus, label: 'New playlist', run: () => views.newPlaylist(tracks) },
    ...(lib.playlists.length ? ['-'] : []),
    ...lib.playlists.map((p) => ({
      icon: '<span class="mi-art">' + mosaic(p.covers, 32) + '</span>',
      label: p.name,
      run: async () => {
        await addToPlaylist(p.id, tracks);
        toast(`Added to ${p.name}`);
        if (location.hash === `#/playlist/${p.id}`) route();
      },
    })),
  ];
}

export function trackMenuItems(t, ctx = {}) {
  const liked = isLiked(t.id);
  const dl = dlState(t.id);
  const artists = (t.artists || []).filter((a) => a.id);
  return [
    { icon: icon.plus, label: 'Add to playlist', sub: () => addToPlaylistItems([t]) },
    ctx.playlist ? { icon: icon.trash, label: 'Remove from this playlist', run: async () => {
      await removeFromPlaylist(ctx.playlist, t.id);
      toast('Removed from playlist');
      route();
    } } : null,
    { icon: liked ? icon.heartFill : icon.heart, label: liked ? 'Remove from Liked Songs' : 'Save to Liked Songs', run: () => likeTrack(t) },
    '-',
    { icon: icon.next1, label: 'Play next', run: () => { player.playNext([t]); toast('Playing next'); } },
    { icon: icon.addQueue, label: 'Add to queue', run: () => { player.addToQueue([t]); toast('Added to queue'); } },
    ctx.queueIndex != null ? { icon: icon.x, label: 'Remove from queue', run: () => player.removeAt(ctx.queueIndex) } : null,
    { icon: icon.radio, label: 'Go to song radio', run: () => player.startRadio(t) },
    '-',
    dl === 'done' || onDevice(t.id)
      ? { icon: icon.downloaded, label: 'Remove download', run: () => removeDownload(t.id).then(() => toast('Download removed')) }
      : dl === 'queued' || dl === 'downloading'
        ? { icon: icon.downloading, label: 'Downloading…', run: () => {} }
        : { icon: icon.download, label: 'Download', run: () => { download([t]); toast('Downloading'); } },
    ...artists.slice(0, 2).map((a) => ({ icon: icon.user, label: artists.length > 1 ? `Go to ${a.name}` : 'Go to artist', run: () => go(`#/artist/${a.id}`) })),
    t.album?.id ? { icon: icon.disc, label: 'Go to album', run: () => go(`#/album/${t.album.id}`) } : null,
    { icon: icon.link, label: 'Copy link', run: () => navigator.clipboard?.writeText(`https://music.youtube.com/watch?v=${t.id}`).then(() => toast('Link copied')) },
  ];
}

const menuHeader = (t) => `${art(t.art, 48)}<div><div class="sheet-title">${esc(t.title)}</div><div class="sheet-sub">${esc(artistsText(t))}</div></div>`;

async function likeTrack(t) {
  try {
    const now = await toggleLike(t);
    toast(now ? 'Added to Liked Songs' : 'Removed from Liked Songs');
  } catch {
    toast('Couldn’t update Liked Songs');
  }
}

function go(hash) {
  closeNow();
  closeQueue();
  location.hash = hash;
}

// ---------- router ----------

const routes = [
  [/^#?\/?$/, views.home, 'home'],
  [/^#\/search(?:\?q=(.*))?$/, (el, m) => views.search(el, { q: m[1] ? decodeURIComponent(m[1]) : '' }), 'search'],
  [/^#\/library$/, views.library, 'library'],
  [/^#\/liked$/, views.liked, 'library'],
  [/^#\/downloads$/, views.downloads, 'library'],
  [/^#\/album\/([^/?]+)/, (el, m) => views.album(el, { id: decodeURIComponent(m[1]) })],
  [/^#\/artist\/([^/?]+)/, (el, m) => views.artist(el, { id: decodeURIComponent(m[1]) })],
  [/^#\/yt\/([^/?]+)/, (el, m) => views.ytPlaylist(el, { id: decodeURIComponent(m[1]) })],
  [/^#\/playlist\/([^/?]+)/, (el, m) => views.localPlaylist(el, { id: decodeURIComponent(m[1]) })],
  [/^#\/settings$/, views.settings, 'library'],
];

let handlers = {};
let routeSeq = 0;
const scrollPos = new Map();
let lastHash = location.hash;

async function route() {
  const hash = location.hash || '#/';
  const my = ++routeSeq;
  scrollPos.set(lastHash, main.scrollTop);
  const sameBase = hash.split('?')[0] === lastHash.split('?')[0];
  lastHash = hash;
  for (const [re, fn, tab] of routes) {
    const m = hash.match(re);
    if (!m) continue;
    document.body.dataset.tab = tab || '';
    document.body.classList.toggle('root', !!tab && !/liked|downloads/.test(hash));
    $('#topbar').classList.remove('scrolled');
    if (!(sameBase && hash.startsWith('#/search'))) main.scrollTop = 0;
    const h = await fn(view, m);
    if (my !== routeSeq) return;
    handlers = h || {};
    const y = scrollPos.get(hash);
    if (y && popNav) main.scrollTop = y;
    popNav = false;
    highlightSidebar();
    return;
  }
  location.hash = '#/';
}

let popNav = false;
window.addEventListener('popstate', () => { popNav = true; });
window.addEventListener('hashchange', route);

main.addEventListener('scroll', () => {
  $('#topbar').classList.toggle('scrolled', main.scrollTop > 220);
}, { passive: true });

// ---------- global click delegation ----------

document.addEventListener('click', async (e) => {
  const t = e.target;
  if (t.closest('[data-stop]')) {
    // a link inside a clickable row: let the link navigate, don't trigger the row
    if (t.closest('#now')) closeNow();
    return;
  }

  const act = t.closest('[data-act]');
  if (act && handlers[act.dataset.act]) {
    e.preventDefault();
    return handlers[act.dataset.act](act, e);
  }
  if (t.closest('[data-action="reload"]')) return route();

  // play buttons on cards / quick tiles
  const pb = t.closest('[data-play-album],[data-play-artist],[data-play-yt],[data-play-local],[data-play-liked],[data-card-track]');
  if (pb) {
    e.stopPropagation();
    e.preventDefault();
    return playFromButton(pb);
  }

  // track rows & track cards
  const row = t.closest('[data-list][data-i]');
  if (row) {
    const list = getList(row.dataset.list);
    if (!list) return;
    const i = +row.dataset.i;
    const tr = list.tracks[i];
    if (t.closest('[data-like]')) return likeTrack(tr);
    if (t.closest('[data-menu]')) {
      return openMenu(t.closest('[data-menu]'), trackMenuItems(tr, { playlist: list.opts?.playlist || list.context?.playlist, queueIndex: list.queue ? i : null }), menuHeader(tr));
    }
    if (list.queue) return player.jump(i);
    if (player.current?.id === tr.id && row.classList.contains('playing')) return player.toggle();
    if (list.single || list.tracks.length === 1) return player.playTrack(tr, list.context);
    return player.playList(list.tracks, i, list.context, { shuffle: false });
  }

  const href = t.closest('[data-href]');
  if (href) {
    e.preventDefault();
    return go(href.dataset.href);
  }
});

// right-click on rows opens the menu (desktop)
document.addEventListener('contextmenu', (e) => {
  const row = e.target.closest('[data-list][data-i]');
  if (!row || isMobile()) return;
  const list = getList(row.dataset.list);
  if (!list) return;
  e.preventDefault();
  const tr = list.tracks[+row.dataset.i];
  openMenu({ getBoundingClientRect: () => ({ left: e.clientX, right: e.clientX, top: e.clientY, bottom: e.clientY }) },
    trackMenuItems(tr, { playlist: list.opts?.playlist || list.context?.playlist }), menuHeader(tr));
});

// keyboard: Enter on focused rows/cards
document.addEventListener('keydown', (e) => {
  const tag = e.target.tagName;
  const typing = tag === 'INPUT' || tag === 'TEXTAREA' || e.target.isContentEditable;
  if (e.key === 'Enter' && (e.target.matches('[data-list][data-i],[data-href]'))) {
    e.target.click();
    return;
  }
  if (typing) {
    if (e.key === 'Escape') e.target.blur();
    return;
  }
  if (e.metaKey || e.ctrlKey) {
    if (e.key.toLowerCase() === 'k') { e.preventDefault(); location.hash = '#/search'; setTimeout(() => $('#search-input')?.focus(), 50); }
    return;
  }
  switch (e.key) {
    case ' ': e.preventDefault(); player.toggle(); break;
    case 'ArrowRight': if (e.shiftKey) player.next(); else player.seek(player.time + 5); break;
    case 'ArrowLeft': if (e.shiftKey) player.prev(); else player.seek(player.time - 5); break;
    case 'ArrowUp': if (e.shiftKey) { e.preventDefault(); player.setVolume(player.audio.volume + 0.05); } break;
    case 'ArrowDown': if (e.shiftKey) { e.preventDefault(); player.setVolume(player.audio.volume - 0.05); } break;
    case '/': e.preventDefault(); location.hash = '#/search'; setTimeout(() => $('#search-input')?.focus(), 50); break;
    case 'l': if (player.current) likeTrack(player.current); break;
    case 's': player.toggleShuffle(); break;
    case 'r': player.cycleRepeat(); break;
    case 'q': toggleQueue(); break;
    case 'Escape': closeNow(); closeQueue(); break;
  }
});

async function playFromButton(b) {
  try {
    if (b.dataset.playAlbum) {
      const a = await api.get(`/album/${encodeURIComponent(b.dataset.playAlbum)}`, 300000);
      player.playList(a.tracks, 0, { label: a.title, href: `#/album/${a.id}` }, { shuffle: false });
    } else if (b.dataset.playArtist) {
      const id = b.dataset.playArtist;
      const songs = await api.get(`/artist/${encodeURIComponent(id)}/songs`, 300000);
      const a = await api.get(`/artist/${encodeURIComponent(id)}`, 300000);
      player.playList(songs, 0, { label: a.name, href: `#/artist/${id}` }, { shuffle: false });
    } else if (b.dataset.playYt) {
      const p = await api.get(`/ytplaylist/${encodeURIComponent(b.dataset.playYt)}`, 300000);
      player.playList(p.tracks, 0, { label: p.title, href: `#/yt/${p.id}` }, { shuffle: false });
    } else if (b.dataset.playLocal) {
      const p = await api.get(`/playlists/${encodeURIComponent(b.dataset.playLocal)}`);
      if (!p.tracks.length) return toast('This playlist is empty');
      player.playList(p.tracks, 0, { label: p.name, href: `#/playlist/${p.id}`, playlist: p.id }, { shuffle: false });
    } else if (b.hasAttribute('data-play-liked')) {
      const tracks = await api.get('/liked');
      player.playList(tracks, 0, { label: 'Liked Songs', href: '#/liked' }, { shuffle: false });
    } else if (b.hasAttribute('data-card-track')) {
      const row = b.closest('[data-list][data-i]');
      const list = getList(row.dataset.list);
      const tr = list.tracks[+row.dataset.i];
      player.playTrack(tr, list.context);
    }
  } catch (e) {
    toast('Couldn’t play that');
  }
}

// ---------- sidebar (desktop) ----------

function renderSidebar() {
  const items = [
    { href: '#/liked', cover: `<div class="art liked-art">${icon.heartFill}</div>`, title: 'Liked Songs', sub: `Playlist · ${plural(lib.liked.size, 'song')}`, pin: true },
    { href: '#/downloads', cover: `<div class="art liked-art">${icon.arrowDown}</div>`, title: 'Downloads', sub: `Playlist · ${plural(Object.values(lib.dl).filter((s) => s === 'done').length, 'song')}`, pin: true },
    ...lib.playlists.map((p) => ({ href: `#/playlist/${p.id}`, cover: mosaic(p.covers, 48), title: p.name, sub: `Playlist · ${plural(p.count, 'song')}` })),
    ...[...lib.saved.values()].map((s) => s.kind === 'album'
      ? { href: `#/album/${s.id}`, cover: art(s.art, 48), title: s.title, sub: `Album · ${(s.artists || []).map((a) => a.name).join(', ')}` }
      : s.kind === 'artist'
        ? { href: `#/artist/${s.id}`, cover: art(s.art, 48, '', true), title: s.name, sub: 'Artist', round: true }
        : { href: `#/yt/${s.id}`, cover: art(s.art, 48), title: s.title, sub: `Playlist · ${s.author || ''}` }),
  ];
  $('#side-lib').innerHTML = items.map(views.libRow).join('');
}

function highlightSidebar() {
  const h = location.hash || '#/';
  document.querySelectorAll('.side-nav a, .tabbar a').forEach((a) => a.classList.toggle('active', a.dataset.tab === document.body.dataset.tab));
  document.querySelectorAll('#side-lib .lib-row').forEach((a) => a.classList.toggle('active', a.getAttribute('href') === h));
}

$('#side-create').addEventListener('click', () => views.newPlaylist());

// ---------- player bar + now playing ----------

const bar = $('#player');
const nowEl = $('#now');

function renderTrackInfo() {
  const t = player.current;
  document.body.classList.toggle('has-track', !!t);
  if (!t) return;
  const artHtml = art(t.art, 64);
  $('#pb-art').innerHTML = artHtml;
  $('#pb-title').innerHTML = `<span>${esc(t.title)}</span>`;
  $('#pb-title').title = t.title;
  $('#pb-artist').innerHTML = artistLinks(t);
  $('#np-art').innerHTML = t.art ? `<img src="${esc(img(t.art, 720))}" alt="" onerror="this.onerror=null;this.src=window.ART_PH">` : `<div class="art ph">${icon.note}</div>`;
  $('#np-bg').style.backgroundImage = t.art ? `url("${img(t.art, 96)}")` : '';
  $('#np-title').textContent = t.title;
  $('#np-artist').innerHTML = artistLinks(t);
  $('#np-context').textContent = t._auto ? 'Autoplay' : player.context?.label || '';
  $('#np-context').dataset.href = player.context?.href || '';
  renderLike();
  renderDl();
  if (lyricsOpen) loadLyrics();
  // marquee for long titles
  requestAnimationFrame(() => {
    const el = $('#pb-title');
    el.classList.toggle('marquee', el.scrollWidth > el.clientWidth + 2);
  });
}

function renderLike() {
  const t = player.current;
  if (!t) return;
  const liked = isLiked(t.id);
  for (const b of document.querySelectorAll('[data-pl="like"]')) {
    b.innerHTML = liked ? icon.heartFill : icon.heart;
    b.classList.toggle('on', liked);
  }
}

function renderDl() {
  const t = player.current;
  if (!t) return;
  const s = dlState(t.id);
  const b = $('#np-dl');
  b.innerHTML = s === 'done' || onDevice(t.id) ? icon.downloaded : s === 'queued' || s === 'downloading' ? icon.downloading : icon.download;
  b.classList.toggle('on', isDownloaded(t.id));
}

function renderState() {
  const playing = player.playing;
  for (const b of document.querySelectorAll('[data-pl="toggle"]')) {
    b.innerHTML = playing ? icon.pause : icon.play;
    b.setAttribute('aria-label', playing ? 'Pause' : 'Play');
  }
  document.body.classList.toggle('is-playing', playing);
}

function renderMode() {
  for (const b of document.querySelectorAll('[data-pl="shuffle"]')) b.classList.toggle('on', player.shuffle);
  for (const b of document.querySelectorAll('[data-pl="repeat"]')) {
    b.classList.toggle('on', player.repeat !== 'off');
    b.innerHTML = player.repeat === 'one' ? icon.repeat1 : icon.repeat;
  }
}

let seeking = false;
function renderTime() {
  const d = player.duration, t = player.time;
  const p = d ? (t / d) * 100 : 0;
  if (!seeking) {
    for (const s of document.querySelectorAll('.seek')) {
      s.value = d ? Math.round((t / d) * 1000) : 0;
      s.style.setProperty('--p', p + '%');
    }
    for (const e of document.querySelectorAll('[data-pl="cur"]')) e.textContent = fmtTime(t);
  }
  for (const e of document.querySelectorAll('[data-pl="dur"]')) e.textContent = fmtTime(d);
  $('#mini-progress').style.transform = `scaleX(${p / 100})`;
}

for (const s of document.querySelectorAll('.seek')) {
  s.addEventListener('input', () => {
    seeking = true;
    const v = s.value / 1000;
    s.style.setProperty('--p', v * 100 + '%');
    for (const e of document.querySelectorAll('[data-pl="cur"]')) e.textContent = fmtTime(v * player.duration);
  });
  s.addEventListener('change', () => {
    player.seek((s.value / 1000) * player.duration);
    seeking = false;
  });
}

const vol = $('#volume');
function renderVolume() {
  const v = player.audio.muted ? 0 : player.audio.volume;
  vol.value = Math.round(v * 100);
  vol.style.setProperty('--p', v * 100 + '%');
  $('#mute').innerHTML = v === 0 ? icon.mute : v < 0.5 ? icon.volumeLow : icon.volume;
}
vol.addEventListener('input', () => { player.setVolume(vol.value / 100); renderVolume(); });
player.audio.addEventListener('volumechange', renderVolume);
let lastVol = 1;
$('#mute').addEventListener('click', () => {
  if (player.audio.volume > 0 && !player.audio.muted) { lastVol = player.audio.volume; player.setVolume(0); } else player.setVolume(lastVol || 0.7);
  renderVolume();
});

document.addEventListener('click', (e) => {
  const b = e.target.closest('[data-pl]');
  if (!b) return;
  const t = player.current;
  switch (b.dataset.pl) {
    case 'toggle': e.stopPropagation(); player.toggle(); break;
    case 'next': e.stopPropagation(); player.next(); break;
    case 'prev': e.stopPropagation(); player.prev(); break;
    case 'shuffle': player.toggleShuffle(); break;
    case 'repeat': player.cycleRepeat(); break;
    case 'like': e.stopPropagation(); if (t) likeTrack(t); break;
    case 'queue': toggleQueue(); break;
    case 'lyrics': toggleLyrics(); break;
    case 'open': openNow(); break;
    case 'close': closeNow(); break;
    case 'dl':
      if (!t) break;
      if (isDownloaded(t.id)) removeDownload(t.id).then(() => toast('Download removed'));
      else if (!dlState(t.id) || dlState(t.id) === 'error') { download([t]); toast('Downloading'); }
      break;
    case 'more':
      if (t) openMenu(b, trackMenuItems(t), menuHeader(t));
      break;
  }
});

// mobile mini player: tap to open now playing
$('#player').addEventListener('click', (e) => {
  if (!isMobile() || e.target.closest('button, a')) return;
  openNow();
});
$('#pb-art').addEventListener('click', () => !isMobile() && openNow());
$('#np-context').addEventListener('click', (e) => { const h = e.currentTarget.dataset.href; if (h) go(h); });

function openNow() {
  if (!player.current) return;
  nowEl.classList.add('open');
  document.body.classList.add('now-open');
  history.pushState({ now: true }, '', location.hash);
}
function closeNow() {
  if (!nowEl.classList.contains('open')) return;
  nowEl.classList.remove('open');
  document.body.classList.remove('now-open');
}
window.addEventListener('popstate', () => { closeNow(); closeQueue(); });

// swipe down to close now playing (mobile)
{
  let y0 = null, dy = 0;
  const sheet = $('#now');
  sheet.addEventListener('touchstart', (e) => {
    if (e.target.closest('input, .np-lyrics, .queue')) return;
    y0 = e.touches[0].clientY; dy = 0;
  }, { passive: true });
  sheet.addEventListener('touchmove', (e) => {
    if (y0 == null) return;
    dy = Math.max(0, e.touches[0].clientY - y0);
    sheet.style.transform = `translateY(${dy}px)`;
    sheet.style.transition = 'none';
  }, { passive: true });
  sheet.addEventListener('touchend', () => {
    if (y0 == null) return;
    sheet.style.transition = '';
    sheet.style.transform = '';
    if (dy > 120) history.back();
    y0 = null;
  });
}

// ---------- lyrics ----------

let lyricsOpen = false;
async function loadLyrics() {
  const t = player.current;
  const box = $('#np-lyrics');
  if (!t) return;
  box.innerHTML = '<p class="muted">Loading lyrics…</p>';
  try {
    const l = await api.get(`/lyrics/${t.id}`, 3600000);
    if (player.current?.id !== t.id) return;
    box.innerHTML = l?.text ? `<div class="lyrics-text">${esc(l.text).replace(/\n/g, '<br>')}</div>${l.source ? `<p class="muted small">${esc(l.source)}</p>` : ''}` : '<p class="muted">No lyrics for this song.</p>';
  } catch {
    box.innerHTML = '<p class="muted">Couldn’t load lyrics.</p>';
  }
}
function toggleLyrics() {
  lyricsOpen = !lyricsOpen;
  nowEl.classList.toggle('show-lyrics', lyricsOpen);
  document.querySelectorAll('[data-pl="lyrics"]').forEach((b) => b.classList.toggle('on', lyricsOpen));
  if (lyricsOpen) {
    if (!nowEl.classList.contains('open')) openNow();
    loadLyrics();
  }
}

// ---------- queue panel ----------

const queueEl = $('#queue');
function toggleQueue() {
  if (queueEl.classList.contains('open')) closeQueue();
  else {
    queueEl.classList.add('open');
    document.body.classList.add('queue-open');
    document.querySelectorAll('[data-pl="queue"]').forEach((b) => b.classList.add('on'));
    renderQueue();
    if (isMobile()) history.pushState({ queue: true }, '', location.hash);
  }
}
function closeQueue() {
  queueEl.classList.remove('open');
  document.body.classList.remove('queue-open');
  document.querySelectorAll('[data-pl="queue"]').forEach((b) => b.classList.remove('on'));
}
$('#queue-close').addEventListener('click', () => (isMobile() ? history.back() : closeQueue()));

function renderQueue() {
  if (!queueEl.classList.contains('open')) return;
  const q = player.queue, i = player.index;
  const st = rowState();
  const key = reg(q, { queue: true });
  const cur = q[i];
  const upcoming = q.slice(i + 1);
  const userCount = upcoming.findIndex((t) => !t._user);
  const nUser = userCount === -1 ? upcoming.length : userCount;
  const row = (t, j) => trackRow(t, j, key, { album: false }, st);
  $('#queue-body').innerHTML = cur
    ? `<h3>Now playing</h3><div class="tracks compact">${row(cur, i)}</div>
      ${nUser ? `<div class="queue-h"><h3>Next in queue</h3><button class="link-btn" data-qclear>Clear</button></div><div class="tracks compact">${upcoming.slice(0, nUser).map((t, j) => row(t, i + 1 + j)).join('')}</div>` : ''}
      ${upcoming.length > nUser ? `<h3>Next from: ${esc(upcoming[nUser]._auto ? 'Autoplay' : player.context?.label || 'Queue')}</h3><div class="tracks compact">${upcoming.slice(nUser, nUser + 100).map((t, j) => row(t, i + 1 + nUser + j)).join('')}</div>` : ''}
      ${!upcoming.length ? `<p class="muted small">${player.autoplay ? 'Autoplay will continue with similar songs.' : 'Nothing up next.'}</p>` : ''}`
    : '<div class="empty small"><p>Your queue is empty.</p></div>';
}
$('#queue-body').addEventListener('click', (e) => {
  if (e.target.closest('[data-qclear]')) {
    const q = player.queue, i = player.index;
    let j = i + 1;
    while (j < q.length && q[j]._user) j++;
    q.splice(i + 1, j - i - 1);
    renderQueue();
  }
});

// ---------- live row updates ----------

function refreshRows() {
  const st = rowState();
  for (const row of document.querySelectorAll('.tr[data-list]')) {
    const list = getList(row.dataset.list);
    if (!list) continue;
    const i = +row.dataset.i;
    const t = list.tracks[i];
    if (!t) continue;
    const playing = st.currentId === t.id;
    const liked = st.liked(t.id);
    const dl = st.dl(t.id) || (st.device(t.id) ? 'done' : '');
    const sig = `${playing}|${liked}|${dl}`;
    if (row.dataset.sig === sig) continue;
    const opts = list.queue ? { album: false } : list.opts || {};
    const extra = row.classList.contains('extra');
    const tmp = document.createElement('div');
    tmp.innerHTML = trackRow(t, i, row.dataset.list, opts, st);
    const n = tmp.firstElementChild;
    if (extra) n.classList.add('extra');
    row.replaceWith(n);
  }
}

// ---------- album art for videos ----------
// Videos only come with a video frame. Ask the server to find the album version's
// cover, then swap it in everywhere that song appears (lists, player, lock screen).

const artChecked = new Set();
let artTimer = null;
const isVideoArt = (u) => !u || u.includes('i.ytimg.com');

function scheduleArt() {
  clearTimeout(artTimer);
  artTimer = setTimeout(upgradeArt, 120);
}

async function upgradeArt() {
  if (!navigator.onLine) return;
  const want = new Map();
  const consider = (t) => {
    if (t && isVideoArt(t.art) && !artChecked.has(t.id) && !want.has(t.id)) want.set(t.id, t);
  };
  for (const el of document.querySelectorAll('#view [data-id], #queue-body [data-id]')) {
    const list = getList(el.dataset.list);
    consider(list?.tracks[+el.dataset.i]);
  }
  consider(player.current);
  player.queue.slice(player.index, player.index + 3).forEach(consider);
  if (!want.size) return;
  const batch = [...want.values()].slice(0, 40);
  batch.forEach((t) => artChecked.add(t.id));
  let found;
  try {
    found = await api.post('/art', { tracks: batch.map((t) => ({ id: t.id, title: t.title, artists: t.artists })) });
  } catch {
    batch.forEach((t) => artChecked.delete(t.id));
    return;
  }
  const hits = Object.entries(found).filter(([, v]) => v?.art);
  if (!hits.length) return;
  const byId = new Map(hits);
  const patch = (t) => {
    const f = t && byId.get(t.id);
    if (!f) return false;
    t.art = f.art;
    if (!t.album && f.album) t.album = f.album;
    return true;
  };
  for (const t of allTracks()) patch(t);
  let currentChanged = false;
  player.queue.forEach((t, i) => { if (patch(t) && i === player.index) currentChanged = true; });
  for (const [id, f] of hits) {
    for (const el of document.querySelectorAll(`[data-id="${CSS.escape(id)}"] img.art`)) {
      const px = Math.max(48, el.clientWidth || 48);
      el.src = img(f.art, px);
    }
  }
  if (currentChanged) {
    renderTrackInfo();
    player.refreshMeta();
  }
  if (want.size > batch.length) scheduleArt();
}

new MutationObserver(scheduleArt).observe($('#view'), { childList: true, subtree: true });
new MutationObserver(scheduleArt).observe($('#queue-body'), { childList: true, subtree: true });

// ---------- events ----------

on('track', () => { renderTrackInfo(); renderTime(); refreshRows(); renderQueue(); scheduleArt(); });
on('state', () => { renderState(); refreshRows(); });
on('time', renderTime);
on('mode', () => { renderMode(); renderQueue(); });
on('queue', renderQueue);
on('buffering', (b) => document.body.classList.toggle('buffering', b));
on('lib', () => {
  renderSidebar();
  highlightSidebar();
  renderLike();
  renderDl();
  refreshRows();
  handlers._onLib?.();
});
on('downloads-idle', () => { if (location.hash === '#/downloads') route(); });

// ---------- offline indicator ----------

function netState() { document.body.classList.toggle('offline', !navigator.onLine); }
window.addEventListener('online', () => { netState(); loadLibrary(); });
window.addEventListener('offline', netState);
netState();

// ---------- boot ----------

renderTrackInfo();
renderState();
renderMode();
renderTime();
renderVolume();
renderSidebar();
// GitHub Pages: find the music server first (usually one quick request). If it isn't
// running, the app still opens normally and keeps checking in the background.
if (ON_PAGES) await findServer();
document.body.classList.toggle('server-offline', !connected);
loadLibrary();
route();

if (ON_PAGES) {
  let checking = false;
  const recheck = async () => {
    if (connected || checking || document.hidden) return;
    checking = true;
    try {
      if (await findServer()) {
        document.body.classList.remove('server-offline');
        await loadLibrary();
        route();
      }
    } finally {
      checking = false;
    }
  };
  setInterval(recheck, 10000);
  window.addEventListener('online', recheck);
  document.addEventListener('visibilitychange', recheck);
}

if ('serviceWorker' in navigator) {
  const hadController = !!navigator.serviceWorker.controller;
  navigator.serviceWorker.register('sw.js').catch((e) => console.warn('SW failed', e));
  // a new version was installed: reload into it, but never interrupt playback
  navigator.serviceWorker.addEventListener('controllerchange', () => {
    if (!hadController) return;
    // if music is playing, the update simply applies on next launch
    if (!player.playing) location.reload();
  });
}
