#!/bin/sh
# Installs (or updates) music on a Mac:
#   curl -fsSL https://v3ai.github.io/music/install-mac.sh | sh
# Downloaded this way rather than through a browser, it opens without the
# "Apple could not verify music" warning. After this the app updates itself.
set -eu
[ "$(uname)" = Darwin ] || { echo "This installer is for macOS." >&2; exit 1; }

tmp=$(mktemp -d)
cleanup() { hdiutil detach "$tmp/mnt" -quiet 2>/dev/null || true; rm -rf "$tmp"; }
trap cleanup EXIT

echo "Downloading music…"
curl -fL --progress-bar -o "$tmp/music.dmg" https://github.com/v3ai/music/releases/latest/download/music-macos.dmg
mkdir "$tmp/mnt"
hdiutil attach -nobrowse -readonly -noautoopen -mountpoint "$tmp/mnt" "$tmp/music.dmg" >/dev/null
src=$(ls -d "$tmp/mnt"/*.app | head -1)

dest=/Applications
[ -w "$dest" ] || { dest="$HOME/Applications"; mkdir -p "$dest"; }
pkill -x music 2>/dev/null || true # close an open copy (only "music", never Apple's Music)
rm -rf "$dest/music.app"
ditto "$src" "$dest/music.app"

echo "Installed $dest/music.app"
open "$dest/music.app"
