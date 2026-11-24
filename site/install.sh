#!/bin/sh
# Installs music from its apt repository, so `sudo apt upgrade` keeps it up to date.
#   curl -fsSL https://v3ai.github.io/music/install.sh | sudo sh
set -eu
[ "$(id -u)" = 0 ] || { echo "Run with sudo: curl -fsSL https://v3ai.github.io/music/install.sh | sudo sh" >&2; exit 1; }
[ "$(dpkg --print-architecture)" = amd64 ] || { echo "music is only built for 64-bit Intel/AMD (amd64)." >&2; exit 1; }
mkdir -p -m 0755 /etc/apt/keyrings
curl -fsSL https://v3ai.github.io/music/apt.gpg -o /etc/apt/keyrings/v3ai-music.gpg
chmod 0644 /etc/apt/keyrings/v3ai-music.gpg
echo "deb [arch=amd64 signed-by=/etc/apt/keyrings/v3ai-music.gpg] https://github.com/v3ai/music/releases/latest/download ./" \
  > /etc/apt/sources.list.d/v3ai-music.list
apt-get update -o Dir::Etc::sourcelist=sources.list.d/v3ai-music.list -o Dir::Etc::sourceparts=- -o APT::Get::List-Cleanup=0
apt-get install -y music
echo "Installed. Open music from your app menu, or run: music"
