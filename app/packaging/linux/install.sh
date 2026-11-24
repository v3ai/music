#!/bin/sh
# Installs music for the current user: ~/.local/share/music + an app-menu entry.
set -e
here="$(cd "$(dirname "$0")" && pwd)"
dest="$HOME/.local/share/music"
mkdir -p "$dest" "$HOME/.local/share/applications" "$HOME/.local/share/icons/hicolor/256x256/apps"
cp -r "$here"/* "$dest"/
cp "$here/music.png" "$HOME/.local/share/icons/hicolor/256x256/apps/music.png"
sed "s|@BIN@|$dest/music|" "$here/music.desktop" > "$HOME/.local/share/applications/music.desktop"
if ! ldconfig -p 2>/dev/null | grep -q libmpv.so; then
  echo "Note: music needs libmpv for audio. Install it with your package manager, e.g."
  echo "  sudo apt install libmpv2     (Debian/Ubuntu)"
  echo "  sudo dnf install mpv-libs    (Fedora)"
  echo "  sudo pacman -S mpv           (Arch)"
fi
echo "Installed. Open “music” from your app menu."
