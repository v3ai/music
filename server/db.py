"""SQLite storage for the local library: tracks, likes, playlists, downloads, history."""
import json
import secrets
import sqlite3
import threading
import time

from .config import DATA_DIR

_conn = sqlite3.connect(DATA_DIR / "music.db", check_same_thread=False, isolation_level=None)
_conn.row_factory = sqlite3.Row
_conn.execute("PRAGMA journal_mode=WAL")
_conn.execute("PRAGMA foreign_keys=ON")
_lock = threading.RLock()

_conn.executescript(
    """
CREATE TABLE IF NOT EXISTS tracks (
    id TEXT PRIMARY KEY,
    meta TEXT NOT NULL
);
CREATE TABLE IF NOT EXISTS likes (
    track_id TEXT PRIMARY KEY,
    added_at REAL NOT NULL
);
CREATE TABLE IF NOT EXISTS playlists (
    id TEXT PRIMARY KEY,
    name TEXT NOT NULL,
    description TEXT NOT NULL DEFAULT '',
    created_at REAL NOT NULL,
    updated_at REAL NOT NULL
);
CREATE TABLE IF NOT EXISTS playlist_tracks (
    playlist_id TEXT NOT NULL REFERENCES playlists(id) ON DELETE CASCADE,
    position INTEGER NOT NULL,
    track_id TEXT NOT NULL,
    added_at REAL NOT NULL
);
CREATE INDEX IF NOT EXISTS playlist_tracks_pl ON playlist_tracks(playlist_id, position);
CREATE TABLE IF NOT EXISTS downloads (
    track_id TEXT PRIMARY KEY,
    status TEXT NOT NULL,          -- queued | downloading | done | error
    progress REAL NOT NULL DEFAULT 0,
    path TEXT,
    size INTEGER,
    error TEXT,
    added_at REAL NOT NULL
);
CREATE TABLE IF NOT EXISTS history (
    track_id TEXT NOT NULL,
    played_at REAL NOT NULL
);
CREATE INDEX IF NOT EXISTS history_time ON history(played_at);
CREATE TABLE IF NOT EXISTS saved (
    kind TEXT NOT NULL,            -- album | artist | playlist (remote YT Music)
    id TEXT NOT NULL,
    meta TEXT NOT NULL,
    added_at REAL NOT NULL,
    PRIMARY KEY (kind, id)
);
"""
)


def _q(sql, args=()):
    with _lock:
        return _conn.execute(sql, args).fetchall()


def _x(sql, args=()):
    with _lock:
        return _conn.execute(sql, args)


# ---------- tracks ----------

def upsert_track(t: dict):
    if not t or not t.get("id"):
        return
    _x("INSERT INTO tracks(id, meta) VALUES(?, ?) ON CONFLICT(id) DO UPDATE SET meta=excluded.meta",
       (t["id"], json.dumps(t)))


def upsert_tracks(ts):
    with _lock:
        _conn.execute("BEGIN")
        try:
            for t in ts:
                upsert_track(t)
            _conn.execute("COMMIT")
        except Exception:
            _conn.execute("ROLLBACK")
            raise


def get_track(tid):
    r = _q("SELECT meta FROM tracks WHERE id=?", (tid,))
    return json.loads(r[0]["meta"]) if r else None


def _tracks_from_rows(rows, key="track_id"):
    out = []
    for r in rows:
        t = get_track(r[key])
        if t:
            out.append(t)
    return out


# ---------- likes ----------

def like(tid, on: bool):
    if on:
        _x("INSERT OR IGNORE INTO likes(track_id, added_at) VALUES(?, ?)", (tid, time.time()))
    else:
        _x("DELETE FROM likes WHERE track_id=?", (tid,))


def liked_ids():
    return [r["track_id"] for r in _q("SELECT track_id FROM likes ORDER BY added_at DESC")]


def liked_tracks():
    return _tracks_from_rows(_q("SELECT track_id FROM likes ORDER BY added_at DESC"))


# ---------- playlists ----------

def _playlist_summary(row):
    first = _q("""SELECT pt.track_id FROM playlist_tracks pt WHERE playlist_id=?
                  ORDER BY position LIMIT 4""", (row["id"],))
    count = _q("SELECT COUNT(*) c FROM playlist_tracks WHERE playlist_id=?", (row["id"],))[0]["c"]
    covers = []
    for r in first:
        t = get_track(r["track_id"])
        if t and t.get("art") and t["art"] not in covers:
            covers.append(t["art"])
    return {
        "id": row["id"], "name": row["name"], "description": row["description"],
        "count": count, "covers": covers, "updated_at": row["updated_at"],
    }


def list_playlists():
    return [_playlist_summary(r) for r in _q("SELECT * FROM playlists ORDER BY updated_at DESC")]


def create_playlist(name, description=""):
    pid = secrets.token_urlsafe(8)
    now = time.time()
    _x("INSERT INTO playlists(id, name, description, created_at, updated_at) VALUES(?,?,?,?,?)",
       (pid, name, description, now, now))
    return pid


def get_playlist(pid):
    rows = _q("SELECT * FROM playlists WHERE id=?", (pid,))
    if not rows:
        return None
    p = _playlist_summary(rows[0])
    p["tracks"] = _tracks_from_rows(
        _q("SELECT track_id FROM playlist_tracks WHERE playlist_id=? ORDER BY position", (pid,)))
    return p


def update_playlist(pid, name=None, description=None):
    if name is not None:
        _x("UPDATE playlists SET name=?, updated_at=? WHERE id=?", (name, time.time(), pid))
    if description is not None:
        _x("UPDATE playlists SET description=?, updated_at=? WHERE id=?", (description, time.time(), pid))


def delete_playlist(pid):
    _x("DELETE FROM playlists WHERE id=?", (pid,))


def add_to_playlist(pid, track_ids):
    with _lock:
        pos = _q("SELECT COALESCE(MAX(position), -1) m FROM playlist_tracks WHERE playlist_id=?", (pid,))[0]["m"]
        existing = {r["track_id"] for r in _q("SELECT track_id FROM playlist_tracks WHERE playlist_id=?", (pid,))}
        now = time.time()
        for tid in track_ids:
            if tid in existing:
                continue
            pos += 1
            existing.add(tid)
            _x("INSERT INTO playlist_tracks(playlist_id, position, track_id, added_at) VALUES(?,?,?,?)",
               (pid, pos, tid, now))
        _x("UPDATE playlists SET updated_at=? WHERE id=?", (now, pid))


def remove_from_playlist(pid, track_id):
    _x("DELETE FROM playlist_tracks WHERE playlist_id=? AND track_id=?", (pid, track_id))
    _x("UPDATE playlists SET updated_at=? WHERE id=?", (time.time(), pid))


def reorder_playlist(pid, track_ids):
    with _lock:
        for i, tid in enumerate(track_ids):
            _x("UPDATE playlist_tracks SET position=? WHERE playlist_id=? AND track_id=?", (i, pid, tid))
        _x("UPDATE playlists SET updated_at=? WHERE id=?", (time.time(), pid))


# ---------- saved albums / artists / remote playlists ----------

def save_item(kind, item_id, meta, on: bool):
    if on:
        _x("INSERT INTO saved(kind, id, meta, added_at) VALUES(?,?,?,?) ON CONFLICT(kind, id) DO UPDATE SET meta=excluded.meta",
           (kind, item_id, json.dumps(meta), time.time()))
    else:
        _x("DELETE FROM saved WHERE kind=? AND id=?", (kind, item_id))


def saved_items():
    return [{"kind": r["kind"], **json.loads(r["meta"]), "id": r["id"]}
            for r in _q("SELECT * FROM saved ORDER BY added_at DESC")]


def is_saved(kind, item_id):
    return bool(_q("SELECT 1 FROM saved WHERE kind=? AND id=?", (kind, item_id)))


# ---------- downloads ----------

def download_row(tid):
    r = _q("SELECT * FROM downloads WHERE track_id=?", (tid,))
    return dict(r[0]) if r else None


def set_download(tid, **fields):
    with _lock:
        if not download_row(tid):
            _x("INSERT INTO downloads(track_id, status, added_at) VALUES(?, 'queued', ?)", (tid, time.time()))
        if fields:
            cols = ", ".join(f"{k}=?" for k in fields)
            _x(f"UPDATE downloads SET {cols} WHERE track_id=?", (*fields.values(), tid))


def delete_download(tid):
    _x("DELETE FROM downloads WHERE track_id=?", (tid,))


def downloads():
    out = []
    for r in _q("SELECT * FROM downloads ORDER BY added_at DESC"):
        t = get_track(r["track_id"])
        if t:
            out.append({**t, "download": {k: r[k] for k in ("status", "progress", "size", "error")}})
    return out


def download_states():
    return {r["track_id"]: r["status"] for r in _q("SELECT track_id, status FROM downloads")}


# ---------- history ----------

def add_history(tid):
    _x("INSERT INTO history(track_id, played_at) VALUES(?, ?)", (tid, time.time()))


def recent_tracks(limit=30):
    rows = _q("""SELECT track_id, MAX(played_at) p FROM history GROUP BY track_id
                 ORDER BY p DESC LIMIT ?""", (limit,))
    return _tracks_from_rows(rows)
