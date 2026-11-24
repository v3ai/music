#!/bin/sh
# Writes signed apt index files next to music-linux-amd64.deb so the release itself is
# an apt repository: deb [signed-by=...] https://github.com/v3ai/music/releases/latest/download ./
# Needs the signing key imported into gpg. Usage: apt-repo.sh <dir>
set -eu
cd "$1"
apt-ftparchive packages . > Packages
gzip -9kf Packages
apt-ftparchive \
  -o APT::FTPArchive::Release::Origin=music \
  -o APT::FTPArchive::Release::Label=music \
  -o APT::FTPArchive::Release::Architectures=amd64 \
  release . > Release
gpg --batch --yes --clearsign -o InRelease Release
gpg --batch --yes --armor --detach-sign -o Release.gpg Release
echo "apt index signed in $1"
