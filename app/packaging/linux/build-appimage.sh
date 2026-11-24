#!/bin/sh
# Packs the Linux build into one double-clickable file: music-linux-x86_64.AppImage
# Run from app/ after `flutter build linux --release`. Usage: build-appimage.sh [version] [out-dir]
set -eu
VERSION=${1:-dev}
OUT=${2:-build}
TOOLS=build/appimage-tools
APPDIR=build/AppDir
P=packaging/linux

mkdir -p "$TOOLS" "$OUT"
fetch() {
  [ -x "$TOOLS/$1" ] && return
  curl -fsSL -o "$TOOLS/$1" "$2"
  chmod +x "$TOOLS/$1"
}
fetch linuxdeploy https://github.com/linuxdeploy/linuxdeploy/releases/download/continuous/linuxdeploy-x86_64.AppImage
fetch appimagetool https://github.com/AppImage/appimagetool/releases/download/continuous/appimagetool-x86_64.AppImage
export APPIMAGE_EXTRACT_AND_RUN=1 # run the tools without FUSE (e.g. in CI)

rm -rf "$APPDIR"
mkdir -p "$APPDIR/usr/share/music"
cp -r build/linux/x64/release/bundle/. "$APPDIR/usr/share/music/"

# The player loads libmpv by name at runtime, so pack it (and what it needs) explicitly.
# linuxdeploy leaves out libraries every desktop already has (glibc, GTK, X11, ...).
mpv=$(ldconfig -p | grep -oE '/[^ ]*libmpv\.so\.[0-9]+$' | head -1)
[ -n "$mpv" ] || { echo "libmpv not found (install libmpv-dev)" >&2; exit 1; }
"$TOOLS/linuxdeploy" --appdir "$APPDIR" \
  --library "$mpv" \
  --desktop-file "$P/io.github.v3ai.music.desktop" \
  --icon-file "$P/io.github.v3ai.music.png" \
  --custom-apprun "$P/AppRun"

# Drop what GTK itself is built on: every system that runs the app has these, and
# older copies from the build machine would clash with the desktop's newer GTK.
for n in libglib-2.0 libgobject-2.0 libgio-2.0 libgmodule-2.0 libgthread-2.0 libffi libpcre2-8 \
  libpango-1.0 libpangocairo-1.0 libpangoft2-1.0 libcairo libcairo-gobject libpixman-1 libgdk_pixbuf-2.0 \
  libepoxy libharfbuzz libfontconfig libfreetype libpng16 libthai libdatrie libX11 libX11-xcb libXau \
  libXdmcp libXext libXfixes libXi libXinerama libXrandr libXrender libXcursor libxcb libxcb-render \
  libxcb-shm libxkbcommon libwayland-client libwayland-cursor libwayland-egl libdbus-1 libmount \
  libblkid libselinux libz; do
  rm -f "$APPDIR/usr/lib/$n.so."*
done

ARCH=x86_64 VERSION="$VERSION" "$TOOLS/appimagetool" --no-appstream "$APPDIR" "$OUT/music-linux-x86_64.AppImage"
echo "built $OUT/music-linux-x86_64.AppImage"
