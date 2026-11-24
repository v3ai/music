import asyncio
import contextlib
import hashlib
import re
from urllib.parse import urlsplit

import httpx
from fastapi import Body, FastAPI, HTTPException, Request
from fastapi.responses import FileResponse, JSONResponse, Response, StreamingResponse
from fastapi.middleware.cors import CORSMiddleware
from fastapi.responses import RedirectResponse
from fastapi.staticfiles import StaticFiles
from starlette.background import BackgroundTask

from . import db, media, ytm
from .config import ALLOWED_ORIGINS, DATA_DIR, WEB_DIR

http: httpx.AsyncClient | None = None


@contextlib.asynccontextmanager
async def lifespan(app):
    global http
    http = httpx.AsyncClient(timeout=httpx.Timeout(20, read=60), follow_redirects=True,
                             limits=httpx.Limits(max_connections=50))
    media.start_downloader()
    yield
    await http.aclose()


app = FastAPI(title="music", lifespan=lifespan, docs_url=None, redoc_url=None)

# Let the GitHub Pages copy of the app talk to this server (including Chrome's
# "private network access" check: a public site reaching a server on your network).
app.add_middleware(
    CORSMiddleware,
    allow_origins=ALLOWED_ORIGINS,
    allow_methods=["*"],
    allow_headers=["*"],
    allow_private_network=True,
    expose_headers=["Content-Range", "Content-Length", "Accept-Ranges"],
    max_age=86400,
)


async def run(fn, *args):
    try:
        return await asyncio.to_thread(fn, *args)
    except HTTPException:
        raise
    except Exception as e:  # upstream (YouTube) failures
        raise HTTPException(502, f"{type(e).__name__}: {e}"[:300])


def _apply_art(tracks):
    """Swap video frames for album art we've already found."""
    vids = [t["id"] for t in tracks if ytm.is_video_art(t.get("art"))]
    if not vids:
        return tracks
    found = db.art_lookup(vids)
    for t in tracks:
        f = found.get(t["id"])
        if f:
            t["art"] = f["art"]
            if not t.get("album") and f.get("album"):
                t["album"] = f["album"]
    return tracks


def _with_state(tracks):
    """Annotate tracks with liked / downloaded flags (and album art for videos)."""
    _apply_art(tracks)
    liked = set(db.liked_ids())
    dls = db.download_states()
    for t in tracks:
        t["liked"] = t["id"] in liked
        t["dl"] = dls.get(t["id"])
    return tracks


# ---------- browse ----------

@app.get("/api/home")
async def home():
    try:
        shelves = await run(ytm.home)
    except HTTPException:
        shelves = []
    for sh in shelves:
        _apply_art([i for i in sh["items"] if i.get("kind") == "track"])
    return {
        "recent": _with_state(db.recent_tracks(20)),
        "playlists": db.list_playlists()[:8],
        "saved": db.saved_items()[:12],
        "shelves": shelves,
    }


@app.get("/api/search")
async def search(q: str):
    r = await run(ytm.search, q.strip())
    _with_state(r["songs"])
    _with_state(r["videos"])
    if r["top"] and r["top"]["kind"] == "track":
        _apply_art([r["top"]])
    return r


@app.get("/api/search/songs")
async def search_songs(q: str):
    return _with_state(await run(ytm.search_songs, q.strip()))


@app.get("/api/suggest")
async def suggest(q: str):
    return await run(ytm.suggestions, q.strip()) if q.strip() else []


@app.get("/api/album/{bid}")
async def album(bid: str):
    a = dict(await run(ytm.album, bid))
    a["tracks"] = _with_state([dict(t) for t in a["tracks"]])
    a["saved"] = db.is_saved("album", bid)
    return a


@app.get("/api/artist/{cid}")
async def artist(cid: str):
    a = dict(await run(ytm.artist, cid))
    a["songs"] = _with_state([dict(t) for t in a["songs"]])
    a["videos"] = _with_state([dict(t) for t in a["videos"]])
    a["saved"] = db.is_saved("artist", cid)
    return a


@app.get("/api/artist/{cid}/songs")
async def artist_songs(cid: str):
    a = await run(ytm.artist, cid)
    if not a.get("songs_playlist"):
        return _with_state([dict(t) for t in a["songs"]])
    p = await run(ytm.playlist, a["songs_playlist"])
    return _with_state([dict(t) for t in p["tracks"]])


@app.get("/api/ytplaylist/{pid}")
async def yt_playlist(pid: str):
    p = dict(await run(ytm.playlist, pid))
    p["tracks"] = _with_state([dict(t) for t in p["tracks"]])
    p["saved"] = db.is_saved("playlist", pid)
    return p


@app.get("/api/radio/{vid}")
async def radio(vid: str):
    return _with_state([dict(t) for t in await run(ytm.radio, vid)])


@app.get("/api/lyrics/{vid}")
async def lyrics(vid: str):
    return await run(ytm.lyrics, vid)


# ---------- artwork proxy + disk cache ----------
# Browsers loading a page full of covers straight from Google get rate-limited (429),
# leaving blank artwork. Instead the app loads covers from here: we fetch each image
# once (a few at a time, retrying politely), keep it on disk, and serve it forever.

ART_HOSTS = ("googleusercontent.com", "ggpht.com", "ytimg.com")
ART_DIR = DATA_DIR / "art"
_img_sem = asyncio.Semaphore(6)
_img_headers = {"User-Agent": "Mozilla/5.0 (X11; Linux x86_64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/140.0 Safari/537.36"}
IMG_CACHE = {"Cache-Control": "public, max-age=31536000, immutable"}


def _img_type(b: bytes):
    if b[:3] == b"\xff\xd8\xff":
        return "image/jpeg"
    if b[:8] == b"\x89PNG\r\n\x1a\n":
        return "image/png"
    if b[:4] == b"RIFF" and b[8:12] == b"WEBP":
        return "image/webp"
    if b[:4] in (b"GIF8",):
        return "image/gif"
    return None


async def _fetch_img(url):
    for attempt in range(5):
        try:
            r = await http.get(url, headers=_img_headers)
        except httpx.HTTPError:
            r = None
        if r is not None and r.status_code == 200 and _img_type(r.content):
            return r.content
        if r is not None and r.status_code == 404:
            return None
        await asyncio.sleep(0.4 * 2 ** attempt)
    return None


@app.get("/api/img")
async def image(u: str):
    host = urlsplit(u).hostname or ""
    if urlsplit(u).scheme != "https" or not host.endswith(ART_HOSTS):
        raise HTTPException(400, "not an artwork url")
    key = hashlib.sha1(u.encode()).hexdigest()
    path = ART_DIR / key[:2] / key
    if not path.exists():
        async with _img_sem:
            if not path.exists():
                data = await _fetch_img(u)
                if data is None:
                    # video frames: hq720 doesn't exist for every video; mqdefault always does
                    m = re.search(r"i\.ytimg\.com/vi/([\w-]{11})/(?!mqdefault)", u)
                    if m:
                        data = await _fetch_img(f"https://i.ytimg.com/vi/{m.group(1)}/mqdefault.jpg")
                if data is None:
                    raise HTTPException(404, "artwork not found")
                path.parent.mkdir(parents=True, exist_ok=True)
                tmp = path.with_suffix(".tmp")
                tmp.write_bytes(data)
                tmp.replace(path)
    data = path.read_bytes()
    return Response(data, media_type=_img_type(data) or "image/jpeg", headers=IMG_CACHE)


@app.post("/api/art")
async def find_art(body: dict = Body(...)):
    """Album art for video tracks: {tracks:[{id,title,artists}]} -> {id: {art, album} | null}."""
    tracks = [t for t in (body.get("tracks") or [])[:40] if isinstance(t, dict) and t.get("id")]
    known = db.art_lookup([t["id"] for t in tracks])
    out = {tid: v for tid, v in known.items()}
    todo = [t for t in tracks if t["id"] not in known]

    async def one(t):
        try:
            found = await asyncio.to_thread(ytm.match_song, t.get("title") or "", t.get("artists") or [])
        except Exception:
            return  # network hiccup: don't cache, try again later
        db.art_store(t["id"], found)
        out[t["id"]] = {"art": found["art"], "album": found.get("album")} if found else None

    await asyncio.gather(*(one(t) for t in todo))
    return out


# ---------- playback ----------

CHUNK = 4 * 1024 * 1024  # upstream request size


@app.api_route("/api/stream/{vid}", methods=["GET", "HEAD"])
async def stream(vid: str, request: Request):
    local = media.file_for(vid)
    if local:
        return FileResponse(local, media_type="audio/mp4", headers={"Cache-Control": "private, max-age=86400"})

    # YouTube throttles un-ranged requests to ~playback speed, but serves explicit
    # byte ranges at full speed. So we always fetch upstream in ranged chunks.
    start, end = 0, None
    client_range = request.headers.get("range")
    if client_range:
        m = re.match(r"bytes=(\d*)-(\d*)", client_range.strip())
        if m and m.group(1):
            start = int(m.group(1))
            end = int(m.group(2)) if m.group(2) else None
        elif m and m.group(2):  # suffix range: last N bytes
            start, end = -int(m.group(2)), None

    for attempt in range(2):
        try:
            s = await media.resolver.get(vid, fresh=attempt > 0)
        except Exception as e:
            raise HTTPException(502, f"Could not load audio: {e}"[:300])
        if start < 0 and s.size:
            start = max(0, s.size + start)
        start = max(start, 0)
        first_end = start + CHUNK - 1 if end is None else min(end, start + CHUNK - 1)
        upstream = await http.send(
            http.build_request("GET", s.url, headers={**s.headers, "Range": f"bytes={start}-{first_end}"}),
            stream=True)
        if upstream.status_code in (403, 404, 410) and attempt == 0:
            await upstream.aclose()
            continue
        if upstream.status_code == 416:
            await upstream.aclose()
            return Response(status_code=416, headers={"content-range": f"bytes */{s.size or 0}"})
        if upstream.status_code not in (200, 206):
            await upstream.aclose()
            raise HTTPException(502, f"Upstream error {upstream.status_code}")
        total = s.size
        cr = upstream.headers.get("content-range", "")
        if "/" in cr and cr.rsplit("/", 1)[1].isdigit():
            total = int(cr.rsplit("/", 1)[1])
        if total is None:
            # unknown size: just pass the first response through
            return StreamingResponse(upstream.aiter_raw(), status_code=upstream.status_code,
                                     media_type=s.mime, background=BackgroundTask(upstream.aclose))
        last = total - 1 if end is None else min(end, total - 1)
        length = last - start + 1
        out = {
            "content-type": s.mime, "accept-ranges": "bytes", "content-length": str(length),
            "cache-control": "no-store",
        }
        status = 200
        if client_range:
            status = 206
            out["content-range"] = f"bytes {start}-{last}/{total}"
        if request.method == "HEAD":
            await upstream.aclose()
            return Response(status_code=status, headers=out)

        async def body(first=upstream, url=s.url, hdrs=s.headers):
            pos = start
            try:
                async for chunk in first.aiter_raw():
                    pos += len(chunk)
                    yield chunk
            finally:
                await first.aclose()
            while pos <= last:
                stop = min(last, pos + CHUNK - 1)
                async with http.stream("GET", url, headers={**hdrs, "Range": f"bytes={pos}-{stop}"}) as r:
                    if r.status_code not in (200, 206):
                        return
                    async for chunk in r.aiter_raw():
                        pos += len(chunk)
                        yield chunk

        return StreamingResponse(body(), status_code=status, headers=out)
    raise HTTPException(502, "Upstream refused the stream")


@app.post("/api/prefetch/{vid}")
async def prefetch(vid: str):
    if not media.file_for(vid):
        media.resolver.prefetch(vid)
    return {"ok": True}


@app.get("/api/cover/{vid}")
async def cover(vid: str):
    p = media.cover_for(vid)
    if not p:
        raise HTTPException(404)
    return FileResponse(p, media_type="image/jpeg", headers={"Cache-Control": "public, max-age=31536000"})


@app.post("/api/played")
async def played(track: dict = Body(...)):
    db.upsert_track(_clean(track))
    db.add_history(track["id"])
    return {"ok": True}


# ---------- library ----------

TRACK_KEYS = ("id", "title", "artists", "album", "duration", "art", "explicit")


def _clean(t):
    if not isinstance(t, dict) or not t.get("id"):
        raise HTTPException(400, "track required")
    return _apply_art([{k: t.get(k) for k in TRACK_KEYS}])[0]


@app.get("/api/library")
async def library():
    return {
        "liked": db.liked_ids(),
        "playlists": db.list_playlists(),
        "saved": db.saved_items(),
        "downloads": db.download_states(),
    }


@app.get("/api/liked")
async def liked():
    return _with_state(db.liked_tracks())


@app.post("/api/like")
async def like(body: dict = Body(...)):
    t = _clean(body.get("track"))
    db.upsert_track(t)
    db.like(t["id"], bool(body.get("on", True)))
    return {"ok": True}


@app.post("/api/save")
async def save(body: dict = Body(...)):
    item = body.get("item") or {}
    kind = body.get("kind")
    if kind not in ("album", "artist", "playlist") or not item.get("id"):
        raise HTTPException(400, "kind and item.id required")
    meta = {k: item.get(k) for k in ("title", "name", "artists", "author", "art", "year", "type")}
    db.save_item(kind, item["id"], meta, bool(body.get("on", True)))
    return {"ok": True}


@app.get("/api/playlists")
async def playlists():
    return db.list_playlists()


@app.post("/api/playlists")
async def create_playlist(body: dict = Body(...)):
    name = (body.get("name") or "").strip() or "My Playlist"
    pid = db.create_playlist(name, body.get("description") or "")
    tracks = [_clean(t) for t in body.get("tracks") or []]
    if tracks:
        db.upsert_tracks(tracks)
        db.add_to_playlist(pid, [t["id"] for t in tracks])
    return db.get_playlist(pid)


@app.get("/api/playlists/{pid}")
async def get_playlist(pid: str):
    p = db.get_playlist(pid)
    if not p:
        raise HTTPException(404, "Playlist not found")
    _with_state(p["tracks"])
    return p


@app.patch("/api/playlists/{pid}")
async def patch_playlist(pid: str, body: dict = Body(...)):
    db.update_playlist(pid, body.get("name"), body.get("description"))
    return db.get_playlist(pid)


@app.delete("/api/playlists/{pid}")
async def delete_playlist(pid: str):
    db.delete_playlist(pid)
    return {"ok": True}


@app.post("/api/playlists/{pid}/tracks")
async def add_tracks(pid: str, body: dict = Body(...)):
    if not db.get_playlist(pid):
        raise HTTPException(404, "Playlist not found")
    tracks = [_clean(t) for t in body.get("tracks") or []]
    db.upsert_tracks(tracks)
    db.add_to_playlist(pid, [t["id"] for t in tracks])
    return {"ok": True}


@app.delete("/api/playlists/{pid}/tracks/{tid}")
async def remove_track(pid: str, tid: str):
    db.remove_from_playlist(pid, tid)
    return {"ok": True}


@app.put("/api/playlists/{pid}/order")
async def reorder(pid: str, body: dict = Body(...)):
    db.reorder_playlist(pid, body.get("ids") or [])
    return {"ok": True}


# ---------- downloads ----------

@app.get("/api/downloads")
async def downloads():
    return _with_state(db.downloads())


@app.post("/api/downloads")
async def add_downloads(body: dict = Body(...)):
    tracks = [_clean(t) for t in body.get("tracks") or []]
    db.upsert_tracks(tracks)
    for t in tracks:
        media.downloader.enqueue(t["id"])
    return {"ok": True, "queued": len(tracks)}


@app.delete("/api/downloads/{tid}")
async def remove_download(tid: str):
    media.downloader.remove(tid)
    return {"ok": True}


# ---------- static web app ----------

def _web_version():
    """Hash of the web app's files, so the service worker updates whenever they change."""
    h = hashlib.sha1()
    for f in sorted(WEB_DIR.rglob("*")):
        if f.is_file():
            h.update(f.name.encode())
            h.update(f.read_bytes())
    return h.hexdigest()[:10]


@app.get("/sw.js")
async def sw():
    src = (WEB_DIR / "sw.js").read_text().replace("const VERSION = 'v1';", f"const VERSION = '{_web_version()}';")
    return Response(src, media_type="text/javascript",
                    headers={"Cache-Control": "no-cache", "Service-Worker-Allowed": "/"})


@app.exception_handler(404)
async def not_found(request: Request, exc):
    if request.url.path.startswith("/api/"):
        detail = getattr(exc, "detail", "Not found")
        return JSONResponse({"detail": detail}, status_code=404)
    return RedirectResponse("/")


class NoCacheStatic(StaticFiles):
    async def get_response(self, path, scope):
        resp = await super().get_response(path, scope)
        resp.headers.setdefault("Cache-Control", "no-cache")
        return resp


app.mount("/", NoCacheStatic(directory=WEB_DIR, html=True), name="web")
