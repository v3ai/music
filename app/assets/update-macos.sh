#!/bin/sh
# $1 = old app's pid, $2 = new disk image, $3 = installed .app
while kill -0 "$1" 2>/dev/null; do sleep 0.3; done
mnt=$(mktemp -d)
if hdiutil attach -nobrowse -readonly -noautoopen -mountpoint "$mnt" "$2" >/dev/null; then
  src=$(ls -d "$mnt"/*.app | head -1)
  if [ -n "$src" ] && rm -rf "$3.new" && ditto "$src" "$3.new"; then
    rm -rf "$3" && mv "$3.new" "$3"
  fi
  hdiutil detach "$mnt" -quiet
fi
open "$3"
