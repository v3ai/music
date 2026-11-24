"""Audio: resolving stream URLs with yt-dlp, and downloading tracks to disk."""
import asyncio
import re
import shutil
import subprocess
import threading
import time
from pathlib import Path

import httpx
import yt_dlp

from . import db
from .config import DATA_DIR, DOWNLOAD_DIR

# Prefer AAC/m4a: it plays everywhere (including iOS Safari / lock screen).
FORMAT = "bestaudio[ext=m4a]/bestaudio[acodec^=mp4a]/bestaudio/best"

_BASE_OPTS = {
    "quiet": True,
    "no_warnings": True,
    "noplaylist": True,
    "format": FORMAT,
    "cachedir": str(DATA_DIR / "ytdlp-cache"),
}
# Fast path: skip the JavaScript challenge solver (≈1s faster per song). If YouTube
# refuses, fall back to the full extractor that uses deno.
_FAST = {"js_runtimes": {}}


def _info(video_id, download=False, extra=None):
    url = f"https://www.youtube.com/watch?v={video_id}"
    last = None
    for mode in (_FAST, {}):
        opts = {**_BASE_OPTS, **mode, **(extra or {})}
        if not download:
            opts["skip_download"] = True
        try:
            with yt_dlp.YoutubeDL(opts) as ydl:
                info = ydl.extract_info(url, download=download)
                if download:
                    info["_filename"] = ydl.prepare_filename(info)
                if info.get("url") or download:
                    return info
        except yt_dlp.utils.DownloadError as e:
            last = e
    raise last or RuntimeError("no playable audio")


class Stream:
    __slots__ = ("url", "headers", "mime", "size", "expires")

    def __init__(self, url, headers, mime, size, expires):
        self.url, self.headers, self.mime, self.size, self.expires = url, headers, mime, size, expires


def _extract(video_id) -> Stream:
    info = _info(video_id)
    url = info["url"]
    m = re.search(r"[?&]expire=(\d+)", url)
    expires = int(m.group(1)) - 300 if m else time.time() + 3 * 3600
    ext = info.get("ext") or "m4a"
    mime = {"m4a": "audio/mp4", "mp4": "audio/mp4", "webm": "audio/webm", "opus": "audio/ogg"}.get(ext, "audio/mp4")
    headers = {k: v for k, v in (info.get("http_headers") or {}).items() if k.lower() in ("user-agent", "referer", "origin")}
    return Stream(url, headers, mime, info.get("filesize") or info.get("filesize_approx"), expires)


class Resolver:
    """Caches extracted stream URLs and de-duplicates concurrent lookups."""

    def __init__(self):
        self._cache: dict[str, Stream] = {}
        self._pending: dict[str, asyncio.Future] = {}

    async def get(self, video_id, fresh=False) -> Stream:
        s = self._cache.get(video_id)
        if s and not fresh and s.expires > time.time():
            return s
        fut = self._pending.get(video_id)
        if fut:
            return await asyncio.shield(fut)
        fut = asyncio.get_running_loop().create_future()
        self._pending[video_id] = fut
        try:
            s = await asyncio.to_thread(_extract, video_id)
            self._cache[video_id] = s
            if len(self._cache) > 500:
                for k in sorted(self._cache, key=lambda k: self._cache[k].expires)[:100]:
                    self._cache.pop(k, None)
            fut.set_result(s)
            return s
        except Exception as e:
            fut.set_exception(e)
            fut.exception()  # mark retrieved
            raise
        finally:
            self._pending.pop(video_id, None)

    def prefetch(self, video_id):
        s = self._cache.get(video_id)
        if (s and s.expires > time.time()) or video_id in self._pending:
            return
        asyncio.get_running_loop().create_task(self._quiet(video_id))

    async def _quiet(self, video_id):
        try:
            await self.get(video_id)
        except Exception:
            pass


resolver = Resolver()


# ---------- downloads ----------

_BAD = re.compile(r'[\\/:*?"<>|\x00-\x1f]+')


def _safe(s, n=80):
    s = _BAD.sub(" ", s or "").strip().strip(".")
    return re.sub(r"\s+", " ", s)[:n] or "Unknown"


def file_for(track_id) -> Path | None:
    row = db.download_row(track_id)
    if row and row["status"] == "done" and row["path"]:
        p = Path(row["path"])
        if p.exists():
            return p
    return None


def cover_for(track_id) -> Path | None:
    p = DOWNLOAD_DIR / ".covers" / f"{track_id}.jpg"
    return p if p.exists() else None


class Downloader:
    def __init__(self):
        self._q: "queue.Queue[str]"
        import queue
        self._q = queue.Queue()
        self._thread = threading.Thread(target=self._run, daemon=True, name="downloader")
        self._thread.start()
        # resume anything that was interrupted
        for tid, status in db.download_states().items():
            if status in ("queued", "downloading"):
                self._q.put(tid)

    def enqueue(self, track_id):
        row = db.download_row(track_id)
        if row and row["status"] in ("queued", "downloading"):
            return
        if row and row["status"] == "done" and file_for(track_id):
            return
        db.set_download(track_id, status="queued", progress=0, error=None)
        self._q.put(track_id)

    def remove(self, track_id):
        p = file_for(track_id)
        if p:
            p.unlink(missing_ok=True)
        c = cover_for(track_id)
        if c:
            c.unlink(missing_ok=True)
        db.delete_download(track_id)

    def _run(self):
        while True:
            tid = self._q.get()
            row = db.download_row(tid)
            if not row or row["status"] == "done":
                continue
            try:
                self._download(tid)
            except Exception as e:  # noqa: BLE001
                db.set_download(tid, status="error", error=str(e)[:300])

    def _download(self, tid):
        t = db.get_track(tid) or {"id": tid, "title": tid, "artists": []}
        db.set_download(tid, status="downloading", progress=0)
        artist = ", ".join(a["name"] for a in t.get("artists") or []) or "Unknown Artist"
        base = DOWNLOAD_DIR / _safe(artist.split(",")[0]) / f"{_safe(artist)} - {_safe(t.get('title'))} [{tid}]"
        base.parent.mkdir(parents=True, exist_ok=True)
        tmpdir = DOWNLOAD_DIR / ".tmp"
        tmpdir.mkdir(exist_ok=True)

        last = [0.0]

        def hook(d):
            if d.get("status") == "downloading":
                total = d.get("total_bytes") or d.get("total_bytes_estimate") or 0
                if total and time.time() - last[0] > 0.5:
                    last[0] = time.time()
                    db.set_download(tid, progress=round(d.get("downloaded_bytes", 0) / total, 3))

        info = _info(tid, download=True, extra={
            "outtmpl": str(tmpdir / f"{tid}.%(ext)s"), "progress_hooks": [hook],
        })
        src = Path(info["_filename"])

        # cover art
        covers = DOWNLOAD_DIR / ".covers"
        covers.mkdir(exist_ok=True)
        cover = covers / f"{tid}.jpg"
        art = t.get("art")
        if art:
            big = re.sub(r"=w\d+-h\d+[^/]*$", "=w1200-h1200-l90-rj", art)
            try:
                r = httpx.get(big, timeout=20, follow_redirects=True)
                r.raise_for_status()
                cover.write_bytes(r.content)
            except Exception:
                cover = None
        else:
            cover = None

        dest = base.with_suffix(".m4a")
        cmd = ["ffmpeg", "-y", "-loglevel", "error", "-i", str(src)]
        if cover:
            cmd += ["-i", str(cover), "-map", "0:a", "-map", "1:v", "-c:v", "copy", "-disposition:v", "attached_pic"]
        else:
            cmd += ["-map", "0:a"]
        cmd += ["-c:a", "copy" if src.suffix == ".m4a" else "aac", "-b:a", "256k"]
        meta = {
            "title": t.get("title"), "artist": artist,
            "album": (t.get("album") or {}).get("name"), "comment": f"https://music.youtube.com/watch?v={tid}",
        }
        for k, v in meta.items():
            if v:
                cmd += ["-metadata", f"{k}={v}"]
        cmd += ["-movflags", "+faststart", str(dest)]
        if shutil.which("ffmpeg"):
            res = subprocess.run(cmd, capture_output=True, text=True)
            if res.returncode != 0:
                raise RuntimeError(res.stderr.strip()[-300:] or "ffmpeg failed")
            src.unlink(missing_ok=True)
        else:
            dest = base.with_suffix(src.suffix)
            shutil.move(src, dest)
        db.set_download(tid, status="done", progress=1, path=str(dest), size=dest.stat().st_size, error=None)


downloader: Downloader | None = None


def start_downloader():
    global downloader
    if downloader is None:
        downloader = Downloader()
    return downloader
