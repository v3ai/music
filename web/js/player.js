// Playback engine: one <audio> element, a queue, shuffle/repeat, autoplay radio,
// lock-screen / notification controls via the Media Session API, and state persistence.

import { api, emit, slim } from './state.js';
import { apiUrl } from './config.js';
import { img, artistsText, toast } from './ui.js';

const STORE = 'music.player';

class Player {
  constructor() {
    this.audio = document.getElementById('audio');
    this.queue = []; // tracks
    this.index = -1;
    this.original = null; // un-shuffled order while shuffle is on
    this.shuffle = false;
    this.repeat = 'off'; // off | all | one
    this.autoplay = true;
    this.context = null; // {label, href}
    this.retried = false;
    this.playedLogged = false;
    this._restore();
    this._wire();
  }

  get current() { return this.queue[this.index] || null; }
  get playing() { return !this.audio.paused; }
  get time() { return this.audio.currentTime || this._resumeAt || 0; }
  get duration() {
    const d = this.audio.duration;
    return isFinite(d) && d > 0 ? d : this.current?.duration || 0;
  }

  // ---------- queue ops ----------

  /** Replace the queue with `tracks` and start at index `i`. */
  playList(tracks, i = 0, context = null, { shuffle } = {}) {
    if (!tracks?.length) return;
    tracks = tracks.map(slim);
    if (shuffle !== undefined) this.shuffle = shuffle;
    this.context = context;
    if (this.shuffle) {
      this.original = tracks.slice();
      const first = shuffle && i === 0 ? Math.floor(Math.random() * tracks.length) : i;
      const head = tracks[first];
      const rest = tracks.filter((_, j) => j !== first);
      this.queue = [head, ...shuffleArr(rest)];
      this.index = 0;
    } else {
      this.original = null;
      this.queue = tracks;
      this.index = Math.max(0, Math.min(i, tracks.length - 1));
    }
    this._load(true);
    emit('queue');
  }

  playTrack(t, context = null) {
    // single track: play it, then autoplay radio continues
    this.playList([t], 0, context);
  }

  playNext(tracks) {
    tracks = [].concat(tracks).map((t) => ({ ...slim(t), _user: true }));
    if (this.index < 0) return this.playList(tracks, 0);
    this.queue.splice(this.index + 1, 0, ...tracks);
    this.original?.push(...tracks);
    emit('queue');
    this._prefetch();
  }

  addToQueue(tracks) {
    tracks = [].concat(tracks).map((t) => ({ ...slim(t), _user: true }));
    if (this.index < 0) return this.playList(tracks, 0);
    let at = this.index + 1;
    while (at < this.queue.length && this.queue[at]._user) at++;
    this.queue.splice(at, 0, ...tracks);
    this.original?.push(...tracks);
    emit('queue');
    this._prefetch();
  }

  removeAt(i) {
    if (i === this.index || i < 0 || i >= this.queue.length) return;
    const [t] = this.queue.splice(i, 1);
    if (i < this.index) this.index--;
    if (this.original) this.original = this.original.filter((x) => x !== t);
    emit('queue');
    this._save();
  }

  jump(i) {
    if (i < 0 || i >= this.queue.length) return;
    this.index = i;
    this._load(true);
    emit('queue');
  }

  clearUpcoming() {
    this.queue = this.queue.slice(0, this.index + 1);
    this.original = null;
    emit('queue');
    this._save();
  }

  // ---------- transport ----------

  toggle() {
    if (!this.current) return;
    if (this.audio.paused) this.play();
    else this.pause();
  }

  play() {
    if (!this.current) return;
    if (!this.audio.src) this._load(true);
    const p = this.audio.play();
    p?.catch((e) => { if (e.name !== 'AbortError') console.warn(e); });
  }

  pause() { this.audio.pause(); }

  async next(auto = false) {
    if (!this.queue.length) return;
    if (auto && this.repeat === 'one') {
      this.audio.currentTime = 0;
      return this.play();
    }
    if (this.index < this.queue.length - 1) {
      this.index++;
    } else if (this.repeat === 'all') {
      this.index = 0;
    } else if (this.autoplay && this.current) {
      const added = await this._extendWithRadio();
      if (!added || this.index >= this.queue.length - 1) { if (auto) this.pause(); return; }
      this.index++;
    } else {
      if (auto) { this.pause(); this.audio.currentTime = 0; }
      return;
    }
    this._load(true);
    emit('queue');
  }

  prev() {
    if (!this.queue.length) return;
    if (this.audio.currentTime > 3 || this.index === 0) {
      this.audio.currentTime = 0;
      return;
    }
    this.index--;
    this._load(true);
    emit('queue');
  }

  seek(t) {
    if (!this.current) return;
    this.audio.currentTime = Math.max(0, Math.min(t, this.duration || t));
    this._updatePosition();
  }

  setVolume(v) {
    this.audio.volume = Math.max(0, Math.min(1, v));
    this.audio.muted = false;
    this._save();
  }

  toggleShuffle() {
    this.shuffle = !this.shuffle;
    const cur = this.current;
    if (this.shuffle) {
      this.original = this.queue.slice();
      const before = this.queue.slice(0, this.index + 1);
      const after = shuffleArr(this.queue.slice(this.index + 1));
      this.queue = [...before, ...after];
    } else if (this.original) {
      this.queue = this.original;
      this.index = Math.max(0, this.queue.indexOf(cur));
      this.original = null;
    }
    emit('queue');
    emit('mode');
    this._save();
  }

  cycleRepeat() {
    this.repeat = { off: 'all', all: 'one', one: 'off' }[this.repeat];
    emit('mode');
    this._save();
  }

  async startRadio(t) {
    t = slim(t);
    try {
      const tracks = await api.get(`/radio/${t.id}`, 600000);
      this.playList([t, ...tracks], 0, { label: `${t.title} Radio` }, { shuffle: false });
    } catch (e) {
      toast('Could not start radio');
    }
  }

  // ---------- internals ----------

  async _extendWithRadio() {
    const seed = this.current;
    if (!seed) return false;
    if (this._extending) return this._extending;
    this._extending = (async () => {
      try {
        const have = new Set(this.queue.map((t) => t.id));
        const tracks = (await api.get(`/radio/${seed.id}`, 600000)).filter((t) => !have.has(t.id));
        if (!tracks.length) return false;
        this.queue.push(...tracks.slice(0, 25).map((t) => ({ ...slim(t), _auto: true })));
        emit('queue');
        this._save();
        return true;
      } catch {
        return false;
      } finally {
        this._extending = null;
      }
    })();
    return this._extending;
  }

  /** Queue up autoplay songs *before* the last song ends, so the switch is instant
   *  (important for background playback on phones, where a slow switch can stop audio). */
  _maybeExtend() {
    if (this.autoplay && this.repeat === 'off' && this.index >= this.queue.length - 1) {
      this._extendWithRadio().then((added) => added && this._prefetch());
    }
  }

  _load(autoplay) {
    const t = this.current;
    if (!t) return;
    this.retried = false;
    this.playedLogged = false;
    this.audio.preload = 'auto';
    this.audio.src = apiUrl(`/stream/${encodeURIComponent(t.id)}`);
    this._resumeAt = 0;
    if (autoplay) this.play();
    this._mediaSession();
    emit('track', t);
    this._save();
    this._prefetch();
    this._maybeExtend();
  }

  _prefetch() {
    const n = this.queue[this.index + 1];
    if (n) navigator.onLine && fetch(apiUrl(`/prefetch/${encodeURIComponent(n.id)}`), { method: 'POST' }).catch(() => {});
  }

  _wire() {
    const a = this.audio;
    a.addEventListener('play', () => { emit('state'); this._ms('playing'); });
    a.addEventListener('pause', () => { emit('state'); this._ms('paused'); this._save(); });
    a.addEventListener('waiting', () => emit('buffering', true));
    a.addEventListener('playing', () => emit('buffering', false));
    a.addEventListener('canplay', () => emit('buffering', false));
    a.addEventListener('loadedmetadata', () => {
      if (this._resumeAt) { a.currentTime = this._resumeAt; this._resumeAt = 0; }
      this._updatePosition();
    });
    let lastSave = 0;
    a.addEventListener('timeupdate', () => {
      emit('time');
      const now = Date.now();
      if (now - lastSave > 5000) { lastSave = now; this._save(); this._updatePosition(); }
      if (!this.playedLogged && a.currentTime > 10 && this.current) {
        this.playedLogged = true;
        api.post('/played', slim(this.current)).catch(() => {});
      }
    });
    a.addEventListener('ended', () => this.next(true));
    a.addEventListener('error', () => {
      if (!this.current || !a.src) return;
      if (!this.retried && navigator.onLine) {
        this.retried = true;
        const pos = a.currentTime;
        a.src = apiUrl(`/stream/${encodeURIComponent(this.current.id)}?r=${Date.now()}`);
        this._resumeAt = pos;
        this.play();
        return;
      }
      toast(navigator.onLine ? `Can't play “${this.current.title}”` : 'You’re offline — this song isn’t downloaded');
      if (this.index < this.queue.length - 1) setTimeout(() => this.next(), 600);
    });

    if ('mediaSession' in navigator) {
      const ms = navigator.mediaSession;
      const set = (k, fn) => { try { ms.setActionHandler(k, fn); } catch {} };
      set('play', () => this.play());
      set('pause', () => this.pause());
      set('previoustrack', () => this.prev());
      set('nexttrack', () => this.next());
      set('seekto', (d) => this.seek(d.seekTime));
      set('stop', () => this.pause());
    }
  }

  /** Re-publish lock-screen metadata (e.g. after better album art was found). */
  refreshMeta() {
    this._mediaSession();
    this._save();
  }

  _ms(state) {
    if ('mediaSession' in navigator) navigator.mediaSession.playbackState = state;
  }

  _mediaSession() {
    const t = this.current;
    if (!('mediaSession' in navigator) || !t) return;
    const sizes = [96, 192, 256, 512];
    navigator.mediaSession.metadata = new MediaMetadata({
      title: t.title,
      artist: artistsText(t),
      album: t.album?.name || '',
      artwork: t.art ? sizes.map((s) => ({ src: new URL(img(t.art, s / Math.min(devicePixelRatio || 1, 2)), location.href).href, sizes: `${s}x${s}`, type: 'image/jpeg' })) : [],
    });
  }

  _updatePosition() {
    if (!('mediaSession' in navigator) || !navigator.mediaSession.setPositionState) return;
    const d = this.duration;
    if (!d) return;
    try {
      navigator.mediaSession.setPositionState({ duration: d, position: Math.min(this.audio.currentTime || 0, d), playbackRate: this.audio.playbackRate || 1 });
    } catch {}
  }

  _save() {
    try {
      const q = this.queue;
      // keep the stored queue bounded
      const start = Math.max(0, this.index - 50);
      localStorage.setItem(STORE, JSON.stringify({
        queue: q.slice(start, this.index + 200),
        index: this.index - start,
        time: this.audio.currentTime || 0,
        shuffle: this.shuffle,
        repeat: this.repeat,
        volume: this.audio.volume,
        autoplay: this.autoplay,
        context: this.context,
      }));
    } catch {}
  }

  _restore() {
    try {
      const s = JSON.parse(localStorage.getItem(STORE) || 'null');
      if (!s) return;
      this.queue = s.queue || [];
      this.index = Math.min(s.index ?? -1, this.queue.length - 1);
      this.shuffle = !!s.shuffle;
      this.repeat = s.repeat || 'off';
      this.autoplay = s.autoplay !== false;
      this.context = s.context || null;
      if (typeof s.volume === 'number') this.audio.volume = s.volume;
      if (this.current) {
        this.audio.preload = 'none';
        this.audio.src = apiUrl(`/stream/${encodeURIComponent(this.current.id)}`);
        this._resumeAt = s.time || 0;
        this._mediaSession();
      }
    } catch {}
  }
}

function shuffleArr(a) {
  a = a.slice();
  for (let i = a.length - 1; i > 0; i--) {
    const j = Math.floor(Math.random() * (i + 1));
    [a[i], a[j]] = [a[j], a[i]];
  }
  return a;
}

export const player = new Player();
