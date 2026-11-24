#!/bin/sh
# Packs the AppImage's folder (build/AppDir, made by build-appimage.sh) into a .deb:
# the app goes in /opt/music, `music` on the PATH, plus the menu entry and icon.
# Usage: build-deb.sh <version> [out-dir]
set -eu
VERSION=$1
OUT=${2:-build}
APPDIR=build/AppDir
P=packaging/linux
ROOT=build/deb
[ -d "$APPDIR/usr/share/music" ] || { echo "run build-appimage.sh first" >&2; exit 1; }

rm -rf "$ROOT"
mkdir -p "$ROOT/DEBIAN" "$ROOT/opt" "$ROOT/usr/bin" "$ROOT/usr/share/applications" "$ROOT/usr/share/icons/hicolor/256x256/apps"
cp -a "$APPDIR" "$ROOT/opt/music"
rm -f "$ROOT/opt/music/.DirIcon" "$ROOT/opt/music/"*.desktop "$ROOT/opt/music/"*.png
ln -s ../../opt/music/AppRun "$ROOT/usr/bin/music"
cp "$P/io.github.v3ai.music.desktop" "$ROOT/usr/share/applications/"
cp "$P/io.github.v3ai.music.png" "$ROOT/usr/share/icons/hicolor/256x256/apps/"

chmod -R u+rwX,go-w,go+rX "$ROOT"

cat > "$ROOT/DEBIAN/control" <<EOF
Package: music
Version: $VERSION
Architecture: amd64
Maintainer: v3ai <v3ai@users.noreply.github.com>
Installed-Size: $(du -sk "$ROOT" | cut -f1)
Depends: libgtk-3-0 | libgtk-3-0t64, libegl1, libgles2, libgl1
Section: sound
Priority: optional
Homepage: https://v3ai.github.io/music/
Description: Ad-free music player
 Search and stream anything on YouTube Music, make playlists, download songs
 for offline listening, and play along with guitar tabs and chords.
EOF

mkdir -p "$OUT"
dpkg-deb --root-owner-group -Zxz --build "$ROOT" "$OUT/music-linux-amd64.deb"
echo "built $OUT/music-linux-amd64.deb"
