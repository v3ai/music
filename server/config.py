import os
import sys
from pathlib import Path

# yt-dlp needs a JavaScript runtime (deno) for YouTube. It's installed into the venv
# via pip; make sure yt-dlp can find it.
_bins = [str(Path(sys.executable).parent)]
try:
    import deno

    _bins.append(str(Path(deno.find_deno_bin()).parent))
except Exception:
    pass
os.environ["PATH"] = os.pathsep.join(_bins + [os.environ.get("PATH", "")])

ROOT = Path(__file__).resolve().parent.parent
DATA_DIR = Path(os.environ.get("MUSIC_DATA", ROOT / "data")).expanduser()
DOWNLOAD_DIR = Path(os.environ.get("MUSIC_DOWNLOADS", DATA_DIR / "downloads")).expanduser()
WEB_DIR = ROOT / "web"
HOST = os.environ.get("MUSIC_HOST", "0.0.0.0")
PORT = int(os.environ.get("MUSIC_PORT", "8484"))
# Optional: YouTube Music UI language / region for search & home
LANG = os.environ.get("MUSIC_LANG", "en")
REGION = os.environ.get("MUSIC_REGION") or None

DATA_DIR.mkdir(parents=True, exist_ok=True)
DOWNLOAD_DIR.mkdir(parents=True, exist_ok=True)
