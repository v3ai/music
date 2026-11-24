"""YouTube Music metadata (search, albums, artists, playlists, radio) via ytmusicapi.

Everything is normalized into a small set of shapes the web client understands:

  track:    {id, title, artists:[{name,id}], album:{name,id}|None, duration, art, explicit}
  album:    {kind:'album', id, title, artists, year, type, art}
  artist:   {kind:'artist', id, name, art}
  playlist: {kind:'playlist', id, title, author, count, art}
"""
import re
import threading
import time
from concurrent.futures import ThreadPoolExecutor

from ytmusicapi import YTMusic

from . import config

_local = threading.local()


def _yt() -> YTMusic:
    # one client per thread: requests.Session is not guaranteed thread-safe
    if not hasattr(_local, "yt"):
        _local.yt = YTMusic(language=config.LANG, location=config.REGION or "")
    return _local.yt


# ---------- tiny TTL cache ----------

_cache: dict = {}
_cache_lock = threading.Lock()


def cached(ttl):
    def deco(fn):
        def wrapper(*args):
            key = (fn.__name__, args)
            now = time.time()
            with _cache_lock:
                hit = _cache.get(key)
                if hit and hit[0] > now:
                    return hit[1]
            val = fn(*args)
            with _cache_lock:
                if len(_cache) > 2000:
                    _cache.clear()
                _cache[key] = (now + ttl, val)
            return val
        return wrapper
    return deco


# ---------- normalization helpers ----------

_SIZE_RE = re.compile(r"=[ws]\d+[^/=]*$")


def art_url(thumbs, size=544):
    """Pick the best thumbnail and ask Google's image server for a square of `size` px."""
    if not thumbs:
        return None
    if isinstance(thumbs, dict):
        thumbs = thumbs.get("thumbnails") or []
    url = thumbs[-1].get("url") if thumbs else None
    if not url:
        return None
    if "googleusercontent.com" in url or "ggpht.com" in url:
        if _SIZE_RE.search(url):
            return _SIZE_RE.sub(f"=w{size}-h{size}-l90-rj", url)
        return url + f"=w{size}-h{size}-l90-rj"
    m = re.search(r"i\.ytimg\.com/vi/([\w-]{11})/", url)
    if m:
        return f"https://i.ytimg.com/vi/{m.group(1)}/hq720.jpg"
    return url


def parse_duration(s):
    if s is None:
        return None
    if isinstance(s, (int, float)):
        return int(s)
    try:
        parts = [int(p) for p in str(s).split(":")]
    except ValueError:
        return None
    secs = 0
    for p in parts:
        secs = secs * 60 + p
    return secs


def _artists(x):
    out = []
    for a in x.get("artists") or []:
        if a and a.get("name"):
            out.append({"name": a["name"], "id": a.get("id")})
    if not out and x.get("author"):
        a = x["author"]
        if isinstance(a, list):
            out = [{"name": i.get("name"), "id": i.get("id")} for i in a if i.get("name")]
        elif isinstance(a, str):
            out = [{"name": a, "id": None}]
    return out


def track(x, album=None, art=None):
    vid = x.get("videoId")
    if not vid:
        return None
    alb = x.get("album")
    if isinstance(alb, dict) and alb.get("name"):
        alb = {"name": alb["name"], "id": alb.get("id")}
    elif album:
        alb = album
    else:
        alb = None
    return {
        "id": vid,
        "title": x.get("title") or "Unknown",
        "artists": _artists(x),
        "album": alb,
        "duration": x.get("duration_seconds") or parse_duration(x.get("duration") or x.get("length")),
        "art": art_url(x.get("thumbnails") or x.get("thumbnail")) or art,
        "explicit": bool(x.get("isExplicit")),
    }


def album_card(x):
    return {
        "kind": "album",
        "id": x.get("browseId"),
        "title": x.get("title"),
        "artists": _artists(x),
        "year": x.get("year"),
        "type": x.get("type") or "Album",
        "art": art_url(x.get("thumbnails")),
    }


def artist_card(x):
    first = (x.get("artists") or [{}])[0] or {}
    return {
        "kind": "artist",
        "id": x.get("browseId") or x.get("channelId") or first.get("id"),
        "name": x.get("artist") or x.get("name") or x.get("title") or first.get("name"),
        "art": art_url(x.get("thumbnails")),
    }


def playlist_card(x):
    pid = x.get("playlistId") or x.get("browseId") or ""
    if pid.startswith("VL"):
        pid = pid[2:]
    author = x.get("author")
    if isinstance(author, list):
        author = ", ".join(a.get("name", "") for a in author if a)
    return {
        "kind": "playlist",
        "id": pid,
        "title": x.get("title"),
        "author": author or (x.get("description") if isinstance(x.get("description"), str) else None),
        "count": x.get("itemCount") or x.get("count"),
        "art": art_url(x.get("thumbnails")),
    }


def any_card(x):
    rt = x.get("resultType")
    if x.get("videoId") and rt not in ("album", "playlist", "artist"):
        t = track(x)
        return {"kind": "track", **t} if t else None
    bid = x.get("browseId") or ""
    if rt == "album" or bid.startswith("MPRE"):
        return album_card(x)
    if rt == "artist" or (bid.startswith("UC") and not x.get("playlistId")):
        return artist_card(x)
    if x.get("playlistId") or rt == "playlist" or bid.startswith("VL"):
        return playlist_card(x)
    return None


# ---------- API ----------

_pool = ThreadPoolExecutor(max_workers=8)


@cached(600)
def search(q):
    # The general search gives the top result + albums/artists/playlists; the songs-only
    # search gives properly-attributed songs (with artist + album), so run both at once.
    songs_f = _pool.submit(search_songs, q)
    res = _yt().search(q, limit=20)
    out = {"top": None, "songs": [], "albums": [], "artists": [], "playlists": [], "videos": []}
    loose_songs = []
    for x in res:
        rt = x.get("resultType")
        card = any_card(x)
        if not card:
            continue
        if x.get("category") == "Top result" and out["top"] is None:
            out["top"] = card
            continue
        if rt == "song":
            loose_songs.append(card)
        elif rt == "video":
            out["videos"].append(card)
        elif rt == "album":
            out["albums"].append(card)
        elif rt == "artist":
            out["artists"].append(card)
        elif rt == "playlist":
            out["playlists"].append(card)
    top = out["top"]
    if top and top["kind"] == "artist":
        # songs shown under an artist top result come without artist info
        for s in loose_songs:
            if not s["artists"]:
                s["artists"] = [{"name": top["name"], "id": top["id"]}]
    try:
        songs = [{"kind": "track", **t} for t in songs_f.result(timeout=15)]
    except Exception:
        songs = []
    out["songs"] = songs or loose_songs
    if top and top["kind"] == "track":
        out["songs"] = [s for s in out["songs"] if s["id"] != top["id"]]
    return out


@cached(3600)
def search_songs(q):
    return [t for t in (track(x) for x in _yt().search(q, filter="songs", limit=40)) if t]


@cached(3600)
def suggestions(q):
    try:
        return _yt().get_search_suggestions(q)[:8]
    except Exception:
        return []


@cached(6 * 3600)
def album(browse_id):
    a = _yt().get_album(browse_id)
    art = art_url(a.get("thumbnails"))
    ref = {"name": a.get("title"), "id": browse_id}
    tracks = []
    for x in a.get("tracks") or []:
        if x.get("isAvailable") is False:
            continue
        t = track(x, album=ref, art=art)
        if t:
            t["art"] = art  # album tracks share the album cover
            tracks.append(t)
    return {
        "kind": "album",
        "id": browse_id,
        "title": a.get("title"),
        "type": a.get("type") or "Album",
        "artists": _artists(a),
        "year": a.get("year"),
        "art": art,
        "duration": a.get("duration_seconds"),
        "description": a.get("description"),
        "tracks": tracks,
        "other": [album_card(v) for v in (a.get("other_versions") or [])][:10],
    }


@cached(6 * 3600)
def artist(channel_id):
    a = _yt().get_artist(channel_id)

    def section(key, fn):
        s = a.get(key) or {}
        return [c for c in (fn(x) for x in s.get("results") or []) if c and c.get("id")]

    return {
        "kind": "artist",
        "id": channel_id,
        "name": a.get("name"),
        "art": art_url(a.get("thumbnails"), 1200),
        "description": a.get("description"),
        "listeners": a.get("monthlyListeners") or a.get("subscribers"),
        "songs": section("songs", track),
        "songs_playlist": (a.get("songs") or {}).get("browseId"),
        "albums": section("albums", album_card),
        "singles": section("singles", album_card),
        "videos": section("videos", track),
        "related": section("related", artist_card),
    }


@cached(3600)
def playlist(playlist_id, limit=300):
    p = _yt().get_playlist(playlist_id, limit=limit)
    tracks = [t for t in (track(x) for x in p.get("tracks") or []) if t]
    author = p.get("author")
    if isinstance(author, dict):
        author = author.get("name")
    return {
        "kind": "playlist",
        "id": playlist_id,
        "title": p.get("title"),
        "author": author,
        "description": p.get("description"),
        "art": art_url(p.get("thumbnails")),
        "count": p.get("trackCount") or len(tracks),
        "tracks": tracks,
    }


@cached(1800)
def radio(video_id):
    w = _yt().get_watch_playlist(videoId=video_id, limit=50, radio=True)
    return [t for t in (track(x) for x in w.get("tracks") or []) if t and t["id"] != video_id]


@cached(1800)
def home():
    shelves = []
    for s in _yt().get_home(limit=8):
        items = [c for c in (any_card(x) for x in s.get("contents") or []) if c]
        if items:
            shelves.append({"title": s.get("title"), "items": items})
    return shelves


@cached(86400)
def lyrics(video_id):
    w = _yt().get_watch_playlist(videoId=video_id, limit=1)
    lid = w.get("lyrics")
    if not lid:
        return None
    try:
        l = _yt().get_lyrics(lid)
    except Exception:
        return None
    return {"text": l.get("lyrics"), "source": l.get("source")} if l else None


# ---------- album art for videos ----------
# Music videos / uploads have no album, only a video frame. Find the matching album
# song on YouTube Music and borrow its album + cover art.

_NOISE = re.compile(
    r"\s*[\(\[][^\)\]]*(official|video|lyric|audio|visuali[sz]er|\bhd\b|\b4k\b|\bhq\b|\bmv\b|clip|"
    r"remaster|explicit|clean|performance|color coded|letra|legendado)[^\)\]]*[\)\]]",
    re.I,
)
_FEAT = re.compile(r"\s+[\(\[]?(ft|feat|featuring)\.?\s.*$", re.I)


def _norm(s):
    return re.sub(r"[^\w]+", "", (s or "").lower())


def _clean_title(t):
    t = _NOISE.sub("", t or "")
    t = _FEAT.sub("", t)
    return t.strip(" -|–—\"'")


def is_video_art(url):
    return not url or "i.ytimg.com" in url


def match_song(title, artists):
    """Return {art, album, song} for the album version of a video, or None."""
    names = [a["name"] for a in artists or [] if a.get("name")]
    t = _clean_title(title)
    for sep in (" - ", " – ", " — ", " | "):
        if sep in t:
            left, right = t.split(sep, 1)
            if not names or any(_norm(n) in _norm(left) or _norm(left) in _norm(n) for n in names):
                names = names or [left.strip()]
                t = _clean_title(right)
            break
    if not t:
        return None
    nt = _norm(t)
    who = _norm(" ".join(names))
    for song in search_songs(f"{names[0] if names else ''} {t}".strip())[:6]:
        st = _norm(_clean_title(song["title"]))
        title_ok = st == nt or (min(len(st), len(nt)) >= 4 and (st.startswith(nt) or nt.startswith(st))
                                and min(len(st), len(nt)) / max(len(st), len(nt)) > 0.6)
        song_artists = [_norm(a["name"]) for a in song["artists"]]
        artist_ok = not who or any(a and (a in who or who in a) for a in song_artists)
        if title_ok and artist_ok and song.get("art"):
            return {"art": song["art"], "album": song.get("album"), "song": song["id"]}
    return None
