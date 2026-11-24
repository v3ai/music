// Page views. Each view renders into `el` and returns a map of action handlers
// (triggered by elements with data-act="name" inside the view).

import { api, lib, device, isSaved, toggleSave, download, removeDownload, createPlaylist, refreshPlaylists, slim, emit } from './state.js';
import { player } from './player.js';
import {
  icon, esc, art, mosaic, card, shelf, reg, trackRow, skeleton, errorView, fmtLong, fmtTime,
  artistLinks, artistsText, toast, prompt, confirmDialog, openMenu,
} from './ui.js';
import { rowState, trackMenuItems, addToPlaylistItems, setTitle } from './main.js';

const TTL = 5 * 60 * 1000;

// ---------- shared pieces ----------

function hero({ cover, type, title, meta, desc, round = false, big = false }) {
  return `<header class="hero${big ? ' hero-big' : ''}">
    <div class="hero-cover${round ? ' round' : ''}">${cover}</div>
    <div class="hero-info">
      ${type ? `<div class="hero-type">${esc(type)}</div>` : ''}
      <h1 class="hero-title${title.length > 28 ? ' long' : ''}">${esc(title)}</h1>
      ${desc ? `<p class="hero-desc">${esc(desc)}</p>` : ''}
      <div class="hero-meta">${meta}</div>
    </div>
  </header>`;
}

function actionBar({ key, save, dl = true, more = true, saveOn = false }) {
  return `<div class="actions">
    <button class="btn-play" data-act="playAll" aria-label="Play">${icon.play}</button>
    <button class="icon-btn${player.shuffle ? ' on' : ''}" data-act="shuffleAll" aria-label="Shuffle">${icon.shuffle}</button>
    ${save ? `<button class="icon-btn lg${saveOn ? ' on' : ''}" data-act="save" aria-label="Save to library">${saveOn ? icon.saved : icon.save}</button>` : ''}
    ${dl ? `<button class="icon-btn lg" data-act="downloadAll" aria-label="Download">${icon.download}</button>` : ''}
    ${more ? `<button class="icon-btn" data-act="more" aria-label="More">${icon.more}</button>` : ''}
  </div>`;
}

function trackList(tracks, key, opts = {}) {
  if (!tracks.length) return `<div class="empty small"><p>${esc(opts.emptyText || 'No songs here yet.')}</p></div>`;
  const st = rowState();
  return `<div class="tracks${opts.num ? ' numbered' : ''}">
    <div class="tracks-head"><div>#</div><div>Title</div><div>${opts.album === false ? '' : 'Album'}</div><div></div><div>${icon.clock}</div><div></div></div>
    ${tracks.map((t, i) => trackRow(t, i, key, opts, st)).join('')}
  </div>`;
}

function listHandlers(tracks, context, extra = {}) {
  return {
    playAll: () => player.playList(tracks, 0, context, { shuffle: false }),
    shuffleAll: () => player.playList(tracks, 0, context, { shuffle: true }),
    downloadAll: () => {
      download(tracks);
      toast(`Downloading ${tracks.length} song${tracks.length === 1 ? '' : 's'}`);
    },
    ...extra,
  };
}

const plural = (n, w) => `${n} ${w}${n === 1 ? '' : 's'}`;
const totalDur = (ts) => ts.reduce((s, t) => s + (t.duration || 0), 0);
const copy = (text) => navigator.clipboard?.writeText(text).then(() => toast('Link copied'), () => toast(text));

// ---------- Home ----------

export async function home(el) {
  const h = new Date().getHours();
  const greet = h < 5 ? 'Good night' : h < 12 ? 'Good morning' : h < 18 ? 'Good afternoon' : 'Good evening';
  setTitle('');
  const cached = api.get('/home', 60000);
  el.innerHTML = `<div class="page"><h1 class="greet">${greet}</h1>${skeleton('list')}</div>`;
  let d;
  try {
    d = await cached;
  } catch (e) {
    el.innerHTML = `<div class="page"><h1 class="greet">${greet}</h1>${offlineHome()}</div>`;
    return;
  }

  const quick = [];
  if (lib.liked.size) quick.push({ href: '#/liked', title: 'Liked Songs', cover: `<div class="art liked-art">${icon.heartFill}</div>`, play: 'data-play-liked' });
  for (const p of lib.playlists.slice(0, 5)) quick.push({ href: `#/playlist/${p.id}`, title: p.name, cover: mosaic(p.covers, 64), play: `data-play-local="${esc(p.id)}"` });
  for (const s of d.saved.slice(0, 8 - quick.length)) {
    const href = s.kind === 'album' ? `#/album/${s.id}` : s.kind === 'artist' ? `#/artist/${s.id}` : `#/yt/${s.id}`;
    const play = s.kind === 'album' ? `data-play-album` : s.kind === 'artist' ? 'data-play-artist' : 'data-play-yt';
    quick.push({ href, title: s.title || s.name, cover: art(s.art, 64, '', s.kind === 'artist'), play: `${play}="${esc(s.id)}"` });
  }
  const recentKey = reg(d.recent);

  el.innerHTML = `<div class="page">
    <h1 class="greet">${greet}</h1>
    ${quick.length ? `<div class="quick">${quick.map((q) => `<div class="quick-item" data-href="${q.href}" role="button" tabindex="0">${q.cover}<span>${esc(q.title)}</span><button class="quick-play" ${q.play} aria-label="Play">${icon.play}</button></div>`).join('')}</div>` : ''}
    ${shelf('Recently played', d.recent.map((t) => ({ kind: 'track', ...t })), { trackList: recentKey })}
    ${d.shelves.map((s) => shelf(s.title, s.items)).join('')}
    ${!d.shelves.length && !d.recent.length ? `<div class="empty"><div class="empty-icon">${icon.search}</div><h2>Find something to play</h2><p>Search for songs, artists and albums.</p><a class="btn" href="#/search">Search</a></div>` : ''}
  </div>`;
}

function offlineHome() {
  const tracks = [...device.values()];
  if (!tracks.length) return errorView('Can’t reach your music server.');
  const key = reg(tracks, { opts: {} });
  return `<p class="muted">You’re offline. Here’s what’s downloaded on this device.</p>${trackList(tracks, key)}`;
}

// ---------- Search ----------

const RECENT_Q = 'music.recentSearches';
const recentSearches = () => { try { return JSON.parse(localStorage.getItem(RECENT_Q) || '[]'); } catch { return []; } };
function rememberSearch(q) {
  const r = [q, ...recentSearches().filter((x) => x.toLowerCase() !== q.toLowerCase())].slice(0, 10);
  try { localStorage.setItem(RECENT_Q, JSON.stringify(r)); } catch {}
}

export async function search(el, params) {
  setTitle('');
  let q = params.q || '';
  el.innerHTML = `<div class="page search-page">
    <form class="searchbar" role="search">
      ${icon.search}
      <input id="search-input" type="search" placeholder="What do you want to listen to?" autocomplete="off" autocapitalize="off" spellcheck="false" enterkeyhint="search" value="${esc(q)}">
      <button type="button" class="searchbar-clear" aria-label="Clear" ${q ? '' : 'hidden'}>${icon.x}</button>
    </form>
    <div id="search-results"></div>
  </div>`;
  const input = el.querySelector('#search-input');
  const out = el.querySelector('#search-results');
  const clear = el.querySelector('.searchbar-clear');
  let seq = 0, timer;

  const showRecent = () => {
    const r = recentSearches();
    out.innerHTML = r.length
      ? `<h2 class="section-title">Recent searches</h2><div class="recent-q">${r.map((x) => `<button class="chip" data-q="${esc(x)}">${esc(x)}</button>`).join('')}</div>`
      : `<div class="empty"><div class="empty-icon">${icon.search}</div><h2>Play what you love</h2><p>Search for artists, songs, albums and playlists.</p></div>`;
  };

  const run = async (query, remember = false) => {
    const my = ++seq;
    const enc = encodeURIComponent(query);
    history.replaceState(null, '', query ? `#/search?q=${enc}` : '#/search');
    if (!query) return showRecent();
    if (!out.querySelector('.results')) out.innerHTML = skeleton('list');
    try {
      const r = await api.get(`/search?q=${enc}`, TTL);
      if (my !== seq) return;
      if (remember) rememberSearch(query);
      renderResults(out, r, query);
    } catch (e) {
      if (my === seq) out.innerHTML = errorView(e, false);
    }
  };

  input.addEventListener('input', () => {
    q = input.value.trim();
    clear.hidden = !input.value;
    clearTimeout(timer);
    timer = setTimeout(() => run(q), 280);
  });
  el.querySelector('form').addEventListener('submit', (e) => {
    e.preventDefault();
    clearTimeout(timer);
    input.blur();
    run(input.value.trim(), true);
  });
  clear.addEventListener('click', () => { input.value = ''; clear.hidden = true; run(''); input.focus(); });
  out.addEventListener('click', (e) => {
    const c = e.target.closest('[data-q]');
    if (c) { input.value = c.dataset.q; clear.hidden = false; run(c.dataset.q, true); }
    if (e.target.closest('[data-href], [data-list]') && q) rememberSearch(q);
  });

  if (q) run(q); else showRecent();
  if (!params.q && !matchMedia('(pointer: coarse)').matches) input.focus();

  return {
    allSongs: async () => {
      out.innerHTML = skeleton('list');
      try {
        const songs = await api.get(`/search/songs?q=${encodeURIComponent(q)}`, TTL);
        const key = reg(songs, { opts: {}, context: { label: `“${q}” in Search`, href: `#/search?q=${encodeURIComponent(q)}` } });
        out.innerHTML = `<div class="results"><button class="chip" data-act="backToAll">${icon.back} All results</button><h2 class="section-title">Songs</h2>${trackList(songs, key)}</div>`;
      } catch (e) { out.innerHTML = errorView(e, false); }
    },
    backToAll: () => run(q),
  };
}

function renderResults(out, r, q) {
  const songs = r.songs.slice(0, 4);
  const sctx = { label: `“${q}” in Search`, href: `#/search?q=${encodeURIComponent(q)}` };
  const songKey = reg(r.songs, { opts: { album: false }, context: sctx });
  const top = r.top;
  let topHtml = '';
  if (top) {
    const isTrack = top.kind === 'track';
    const topKey = isTrack ? reg([top], { context: sctx }) : null;
    const title = top.title || top.name;
    const sub = top.kind === 'artist' ? 'Artist' : top.kind === 'album' ? `${top.type || 'Album'} · ${(top.artists || []).map((a) => a.name).join(', ')}` : top.kind === 'playlist' ? `Playlist · ${top.author || ''}` : `Song · ${artistsText(top)}`;
    const href = top.kind === 'artist' ? `#/artist/${top.id}` : top.kind === 'album' ? `#/album/${top.id}` : top.kind === 'playlist' ? `#/yt/${top.id}` : '';
    const playAttr = isTrack ? `data-card-track` : top.kind === 'artist' ? `data-play-artist="${esc(top.id)}"` : top.kind === 'album' ? `data-play-album="${esc(top.id)}"` : `data-play-yt="${esc(top.id)}"`;
    topHtml = `<div class="top-result" ${isTrack ? `data-list="${topKey}" data-i="0" data-id="${esc(top.id)}"` : `data-href="${href}"`} role="button" tabindex="0">
      ${art(top.art, 120, '', top.kind === 'artist')}
      <div class="top-title">${esc(title)}</div>
      <div class="top-sub">${esc(sub)}</div>
      <button class="card-play" ${playAttr} aria-label="Play">${icon.play}</button>
    </div>`;
  }
  const st = rowState();
  out.innerHTML = `<div class="results">
    ${top || songs.length ? `<div class="results-top">
      ${top ? `<section><h2 class="section-title">Top result</h2>${topHtml}</section>` : ''}
      ${songs.length ? `<section class="results-songs"><h2 class="section-title">Songs</h2><div class="tracks compact">${songs.map((t, i) => trackRow(t, i, songKey, { album: false }, st)).join('')}</div>${r.songs.length > 4 ? `<button class="link-btn" data-act="allSongs">See all songs</button>` : ''}</section>` : ''}
    </div>` : ''}
    ${shelf('Artists', r.artists)}
    ${shelf('Albums', r.albums)}
    ${shelf('Playlists', r.playlists)}
    ${shelf('Videos', r.videos)}
    ${!top && !songs.length && !r.albums.length && !r.artists.length ? `<div class="empty"><h2>No results for “${esc(q)}”</h2><p>Check the spelling, or try different keywords.</p></div>` : ''}
  </div>`;
}

// ---------- Album ----------

export async function album(el, { id }) {
  el.innerHTML = skeleton();
  let a;
  try { a = await api.get(`/album/${encodeURIComponent(id)}`, TTL); } catch (e) { el.innerHTML = errorView(e); return; }
  setTitle(a.title);
  const key = reg(a.tracks, { opts: { num: true, album: false }, context: { label: a.title, href: `#/album/${id}` } });
  const saved = isSaved('album', id);
  const artistsHtml = (a.artists || []).map((x) => (x.id ? `<a href="#/artist/${esc(x.id)}"><b>${esc(x.name)}</b></a>` : `<b>${esc(x.name)}</b>`)).join(', ');
  el.innerHTML = `<div class="page detail">
    ${hero({ cover: art(a.art, 300), type: a.type, title: a.title, meta: [artistsHtml, a.year, plural(a.tracks.length, 'song'), fmtLong(a.duration || totalDur(a.tracks))].filter(Boolean).join(' <span class="dot">·</span> ') })}
    ${actionBar({ key, save: true, saveOn: saved })}
    ${trackList(a.tracks, key, { num: true, album: false })}
    ${a.other?.length ? shelf('Other versions', a.other) : ''}
  </div>`;
  const context = { label: a.title, href: `#/album/${id}` };
  const item = { id, title: a.title, artists: a.artists, art: a.art, year: a.year, type: a.type };
  return listHandlers(a.tracks, context, {
    save: async (btn) => {
      const on = await toggleSave('album', item);
      btn.classList.toggle('on', on);
      btn.innerHTML = on ? icon.saved : icon.save;
      toast(on ? 'Saved to Your Library' : 'Removed from Your Library');
    },
    more: (btn) => openMenu(btn, [
      { icon: icon.addQueue, label: 'Add to queue', run: () => { player.addToQueue(a.tracks); toast('Added to queue'); } },
      { icon: icon.plus, label: 'Add to playlist', sub: () => addToPlaylistItems(a.tracks) },
      '-',
      ...(a.artists || []).filter((x) => x.id).slice(0, 2).map((x) => ({ icon: icon.user, label: `Go to ${x.name}`, run: () => (location.hash = `#/artist/${x.id}`) })),
      { icon: icon.link, label: 'Copy link', run: () => copy(`https://music.youtube.com/browse/${id}`) },
    ], menuHeader(a.art, a.title, (a.artists || []).map((x) => x.name).join(', '))),
  });
}

export function menuHeader(artUrl, title, sub, round = false) {
  return `${art(artUrl, 48, '', round)}<div><div class="sheet-title">${esc(title)}</div><div class="sheet-sub">${esc(sub || '')}</div></div>`;
}

// ---------- Artist ----------

export async function artist(el, { id }) {
  el.innerHTML = skeleton();
  let a;
  try { a = await api.get(`/artist/${encodeURIComponent(id)}`, TTL); } catch (e) { el.innerHTML = errorView(e); return; }
  setTitle(a.name);
  const context = { label: a.name, href: `#/artist/${id}` };
  const key = reg(a.songs, { opts: { noArtist: true, album: true }, context });
  const saved = isSaved('artist', id);
  const st = rowState();
  el.innerHTML = `<div class="page detail artist-page">
    <header class="artist-hero">
      ${a.art ? `<img class="artist-bg" src="${esc(a.art)}" alt="" decoding="async">` : ''}
      <div class="artist-hero-info">
        <h1 class="artist-name">${esc(a.name)}</h1>
        ${a.listeners ? `<div class="hero-meta">${esc(a.listeners)} ${/listener|subscriber/i.test(a.listeners) ? '' : 'monthly listeners'}</div>` : ''}
      </div>
    </header>
    <div class="actions">
      <button class="btn-play" data-act="playAll" aria-label="Play">${icon.play}</button>
      <button class="icon-btn" data-act="shuffleAll" aria-label="Shuffle">${icon.shuffle}</button>
      <button class="btn btn-outline${saved ? ' on' : ''}" data-act="follow">${saved ? 'Following' : 'Follow'}</button>
      <button class="icon-btn" data-act="radio" aria-label="Artist radio">${icon.radio}</button>
    </div>
    ${a.songs.length ? `<section><h2 class="section-title">Popular</h2>
      <div class="tracks numbered popular">${a.songs.slice(0, 10).map((t, i) => trackRow(t, i, key, { num: true, noArtist: true }, st).replace('class="tr', `class="tr${i >= 5 ? ' extra' : ''}`)).join('')}</div>
      ${a.songs.length > 5 ? `<button class="link-btn" data-act="toggleMore">See more</button>` : ''}
    </section>` : ''}
    ${shelf('Albums', a.albums)}
    ${shelf('Singles & EPs', a.singles)}
    ${shelf('Videos', a.videos.map((t) => ({ kind: 'track', ...t })))}
    ${shelf('Fans also like', a.related)}
    ${a.description ? `<section class="about"><h2 class="section-title">About</h2><p>${esc(a.description)}</p></section>` : ''}
  </div>`;
  const item = { id, name: a.name, art: a.art };
  const allSongs = async () => {
    try { return await api.get(`/artist/${encodeURIComponent(id)}/songs`, TTL); } catch { return a.songs; }
  };
  return {
    playAll: async () => player.playList(await allSongs(), 0, context, { shuffle: false }),
    shuffleAll: async () => player.playList(await allSongs(), 0, context, { shuffle: true }),
    radio: () => a.songs[0] && player.startRadio(a.songs[0]),
    follow: async (btn) => {
      const on = await toggleSave('artist', item);
      btn.classList.toggle('on', on);
      btn.textContent = on ? 'Following' : 'Follow';
    },
    toggleMore: (btn) => {
      const list = el.querySelector('.popular');
      list.classList.toggle('show-all');
      btn.textContent = list.classList.contains('show-all') ? 'Show less' : 'See more';
    },
  };
}

// ---------- YouTube Music playlist ----------

export async function ytPlaylist(el, { id }) {
  el.innerHTML = skeleton();
  let p;
  try { p = await api.get(`/ytplaylist/${encodeURIComponent(id)}`, TTL); } catch (e) { el.innerHTML = errorView(e); return; }
  setTitle(p.title);
  const context = { label: p.title, href: `#/yt/${id}` };
  const key = reg(p.tracks, { opts: {}, context });
  const saved = isSaved('playlist', id);
  el.innerHTML = `<div class="page detail">
    ${hero({ cover: art(p.art, 300), type: 'Playlist', title: p.title || 'Playlist', desc: p.description, meta: [p.author ? `<b>${esc(p.author)}</b>` : '', plural(p.tracks.length, 'song'), fmtLong(totalDur(p.tracks))].filter(Boolean).join(' <span class="dot">·</span> ') })}
    ${actionBar({ key, save: true, saveOn: saved })}
    ${trackList(p.tracks, key)}
  </div>`;
  const item = { id, title: p.title, author: p.author, art: p.art };
  return listHandlers(p.tracks, context, {
    save: async (btn) => {
      const on = await toggleSave('playlist', item);
      btn.classList.toggle('on', on);
      btn.innerHTML = on ? icon.saved : icon.save;
      toast(on ? 'Saved to Your Library' : 'Removed from Your Library');
    },
    more: (btn) => openMenu(btn, [
      { icon: icon.addQueue, label: 'Add to queue', run: () => { player.addToQueue(p.tracks); toast('Added to queue'); } },
      { icon: icon.plus, label: 'Copy to a new playlist', run: async () => {
        const np = await createPlaylist(p.title || 'Playlist', p.tracks);
        toast('Playlist created');
        location.hash = `#/playlist/${np.id}`;
      } },
      { icon: icon.link, label: 'Copy link', run: () => copy(`https://music.youtube.com/playlist?list=${id}`) },
    ], menuHeader(p.art, p.title, p.author)),
  });
}

// ---------- Local playlist ----------

export async function localPlaylist(el, { id }) {
  el.innerHTML = skeleton();
  let p;
  try { p = await api.get(`/playlists/${encodeURIComponent(id)}`); } catch (e) { el.innerHTML = errorView(e); return; }
  setTitle(p.name);
  const context = { label: p.name, href: `#/playlist/${id}`, playlist: id };
  const key = reg(p.tracks, { opts: { playlist: id }, context });
  el.innerHTML = `<div class="page detail">
    ${hero({ cover: mosaic(p.covers, 300), type: 'Playlist', title: p.name, desc: p.description, meta: [plural(p.tracks.length, 'song'), fmtLong(totalDur(p.tracks))].filter(Boolean).join(' <span class="dot">·</span> ') })}
    ${actionBar({ key })}
    ${trackList(p.tracks, key, { emptyText: 'Use the ••• menu on any song to add it here.' })}
  </div>`;
  const rename = async () => {
    const name = await prompt({ title: 'Rename playlist', value: p.name });
    if (!name) return;
    await api.patch(`/playlists/${id}`, { name });
    await refreshPlaylists();
    localPlaylist(el, { id });
  };
  return listHandlers(p.tracks, context, {
    rename,
    more: (btn) => openMenu(btn, [
      { icon: icon.edit, label: 'Rename', run: rename },
      { icon: icon.edit, label: 'Edit description', run: async () => {
        const description = await prompt({ title: 'Description', value: p.description || '', placeholder: 'Add an optional description' });
        if (description === null) return;
        await api.patch(`/playlists/${id}`, { description });
        localPlaylist(el, { id });
      } },
      { icon: icon.addQueue, label: 'Add to queue', run: () => { player.addToQueue(p.tracks); toast('Added to queue'); } },
      '-',
      { icon: icon.trash, label: 'Delete playlist', run: async () => {
        if (!(await confirmDialog('Delete playlist?', `This will delete “${p.name}”.`))) return;
        await api.del(`/playlists/${id}`);
        await refreshPlaylists();
        toast('Playlist deleted');
        location.hash = '#/library';
      } },
    ], menuHeader(p.covers?.[0], p.name, plural(p.tracks.length, 'song'))),
  });
}

// ---------- Liked songs ----------

export async function liked(el) {
  setTitle('Liked Songs');
  el.innerHTML = skeleton();
  let tracks;
  try { tracks = await api.get('/liked'); } catch (e) { el.innerHTML = errorView(e); return; }
  const context = { label: 'Liked Songs', href: '#/liked' };
  const key = reg(tracks, { opts: {}, context });
  el.innerHTML = `<div class="page detail">
    ${hero({ cover: `<div class="art liked-art">${icon.heartFill}</div>`, type: 'Playlist', title: 'Liked Songs', meta: plural(tracks.length, 'song') })}
    ${actionBar({ key, more: false })}
    ${trackList(tracks, key, { emptyText: 'Songs you like will appear here. Tap the heart on any song.' })}
  </div>`;
  return listHandlers(tracks, context);
}

// ---------- Downloads ----------

export async function downloads(el) {
  setTitle('Downloads');
  el.innerHTML = skeleton();
  let tracks;
  let offline = false;
  try {
    tracks = await api.get('/downloads');
  } catch {
    offline = true;
    tracks = [...device.values()];
  }
  const context = { label: 'Downloads', href: '#/downloads' };
  const ready = tracks.filter((t) => !t.download || t.download.status === 'done');
  const pending = tracks.filter((t) => t.download && t.download.status !== 'done');
  const key = reg(ready, { opts: { downloads: true }, context });
  const size = tracks.reduce((s, t) => s + (t.download?.size || 0), 0);
  el.innerHTML = `<div class="page detail">
    ${hero({ cover: `<div class="art liked-art">${icon.arrowDown}</div>`, type: offline ? 'On this device' : 'Playlist', title: 'Downloads', meta: [plural(ready.length, 'song'), size ? `${(size / 1048576).toFixed(0)} MB` : '', device.size ? `${device.size} on this device` : ''].filter(Boolean).join(' <span class="dot">·</span> ') })}
    ${actionBar({ key, dl: false, more: false })}
    ${pending.length ? `<section class="dl-pending"><h2 class="section-title">In progress</h2>${pending.map((t) => `
      <div class="dl-row">${art(t.art, 40)}<div class="tr-main"><div class="tr-title">${esc(t.title)}</div><div class="tr-sub">${t.download.status === 'error' ? `Failed: ${esc(t.download.error || '')}` : t.download.status === 'queued' ? 'Waiting…' : `Downloading ${Math.round((t.download.progress || 0) * 100)}%`}</div>
      <div class="dl-bar"><i style="width:${Math.round((t.download.progress || 0) * 100)}%"></i></div></div>
      ${t.download.status === 'error' ? `<button class="icon-btn" data-act="retry" data-tid="${esc(t.id)}" aria-label="Retry">${icon.repeat}</button>` : ''}
      <button class="icon-btn" data-act="cancel" data-tid="${esc(t.id)}" aria-label="Remove">${icon.x}</button></div>`).join('')}</section>` : ''}
    ${trackList(ready, key, { emptyText: 'Download songs, albums and playlists to listen offline.' })}
  </div>`;
  const t2 = (btn) => tracks.find((t) => t.id === btn.dataset.tid);
  return listHandlers(ready, context, {
    retry: (btn) => download([t2(btn)]),
    cancel: async (btn) => { await removeDownload(btn.dataset.tid); downloads(el); },
  });
}

// ---------- Library ----------

let libFilter = 'all';

export async function library(el) {
  setTitle('Your Library');
  const render = () => {
    const items = [];
    if (libFilter === 'all' || libFilter === 'playlists') {
      items.push({ href: '#/liked', cover: `<div class="art liked-art">${icon.heartFill}</div>`, title: 'Liked Songs', sub: `Playlist · ${plural(lib.liked.size, 'song')}`, pin: true });
      items.push({ href: '#/downloads', cover: `<div class="art liked-art">${icon.arrowDown}</div>`, title: 'Downloads', sub: `Playlist · ${plural(Object.values(lib.dl).filter((s) => s === 'done').length, 'song')}`, pin: true });
      for (const p of lib.playlists) items.push({ href: `#/playlist/${p.id}`, cover: mosaic(p.covers, 64), title: p.name, sub: `Playlist · ${plural(p.count, 'song')}` });
    }
    for (const s of lib.saved.values()) {
      if (libFilter === 'all' || libFilter === s.kind + 's') {
        if (s.kind === 'album') items.push({ href: `#/album/${s.id}`, cover: art(s.art, 64), title: s.title, sub: `${s.type || 'Album'} · ${(s.artists || []).map((a) => a.name).join(', ')}` });
        if (s.kind === 'artist') items.push({ href: `#/artist/${s.id}`, cover: art(s.art, 64, '', true), title: s.name, sub: 'Artist', round: true });
        if (s.kind === 'playlist') items.push({ href: `#/yt/${s.id}`, cover: art(s.art, 64), title: s.title, sub: `Playlist · ${s.author || 'YouTube Music'}` });
      }
    }
    el.innerHTML = `<div class="page library-page">
      <div class="lib-head"><h1>Your Library</h1><button class="icon-btn" data-act="create" aria-label="Create playlist">${icon.plus}</button></div>
      <div class="chips">${['all', 'playlists', 'albums', 'artists'].map((f) => `<button class="chip${libFilter === f ? ' on' : ''}" data-act="filter" data-f="${f}">${f === 'all' ? 'All' : f[0].toUpperCase() + f.slice(1)}</button>`).join('')}</div>
      <div class="lib-list">${items.map(libRow).join('') || '<div class="empty small"><p>Nothing here yet.</p></div>'}</div>
    </div>`;
  };
  render();
  return {
    create: () => newPlaylist(),
    filter: (btn) => { libFilter = btn.dataset.f; render(); },
    _onLib: render,
  };
}

export const libRow = (x) => `<a class="lib-row${location.hash === x.href ? ' active' : ''}" href="${x.href}">
  <div class="lib-cover${x.round ? ' round' : ''}">${x.cover}</div>
  <div class="lib-text"><div class="lib-title">${esc(x.title)}</div><div class="lib-sub">${x.pin ? `<span class="pin">${icon.check}</span>` : ''}${esc(x.sub)}</div></div>
</a>`;

export async function newPlaylist(tracks = []) {
  const name = await prompt({ title: 'Create playlist', value: `My Playlist #${lib.playlists.length + 1}`, ok: 'Create' });
  if (!name) return null;
  const p = await createPlaylist(name, tracks);
  toast(tracks.length ? `Added to ${name}` : 'Playlist created');
  if (!tracks.length) location.hash = `#/playlist/${p.id}`;
  return p;
}
