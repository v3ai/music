# music

An ad-free music player for **Android, Windows, macOS and Linux**, powered by YouTube Music.

**Download: https://v3ai.github.io/music/**

It looks and works like a normal streaming app: home feed, search, albums, artists, playlists, Liked Songs, queue, shuffle and repeat, lyrics, guitar tabs and chords, and downloads. Music keeps playing with the screen off or the app in the background, with lock-screen, notification and headphone controls.

- **No ads, no account, no server.** The app talks to YouTube Music directly from your device.
- **Album art everywhere.** Music videos show the cover of the album their song is on.
- **Downloads** are stored inside the app, so they play with no connection.
- **Your library** (likes, playlists, saved albums and artists) lives on your device.
- **Autoplay** keeps playing similar songs when your queue ends.
- **Guitar tabs and chords** from [Ultimate Guitar](https://www.ultimate-guitar.com): the best-rated tab or chord sheet for the song, with chord diagrams, capo and tuning, scrolling along as it plays. The menu lists every version (tabs, chords, bass, ukulele), plus [Songsterr](https://www.songsterr.com) tabs that follow the song bar by bar (tap a bar to jump there, nudge the timing with − / +).

## How it works

```
 app (Flutter, one codebase)
  ├─ lib/yt/        YouTube Music: search, home, albums, artists, playlists, radio, lyrics
  ├─ lib/core/      audio streams, a tiny local server the player streams through,
  │                 playback queue + OS media controls, library, downloads, artwork cache,
  │                 guitar tabs
  └─ lib/ui/        screens: phone layout (tabs + mini player) and desktop layout
                    (sidebar + player bar + queue)
```

YouTube serves full songs only in ranged pieces, so the player streams from a small server inside the app (on `127.0.0.1`), which fetches each song in chunks.

If YouTube changes something and songs stop playing, the stream settings can be fixed for everyone without a new release. Installed apps read [`app/clients.json`](app/clients.json) from this repo when they start.

## Build it yourself

Install [Flutter](https://docs.flutter.dev/get-started/install) (stable), then:

```bash
cd app
flutter run                 # on a connected phone or this computer
flutter build apk           # Android
flutter build linux         # Linux (needs libgtk-3-dev, libmpv-dev)
sh packaging/linux/build-appimage.sh   # …then pack it as an AppImage
sh packaging/linux/build-deb.sh 1.0.0   # …and as a .deb (after the AppImage)
flutter build windows       # Windows
flutter build macos         # macOS
```

`source tool/env.sh` sets up `PATH` if Flutter and the Android SDK live in `~/development/flutter` and `~/Android/Sdk`.

## Releasing

Push a tag to build every platform on GitHub Actions and publish a release. The download page always points at the latest one.

| platform | file | |
|---|---|---|
| Android | `music-android.apk` | open it on the phone to install |
| Windows | `music-windows-setup.exe` | one-click installer, no admin needed |
| macOS | `music-macos.dmg` | drag to Applications |
| Linux | `music-linux-x86_64.AppImage` | one file, adds itself to the app menu on first run |
| Linux (apt) | `curl -fsSL https://v3ai.github.io/music/install.sh \| sudo sh` | adds the apt repository, so `apt upgrade` updates it |

`app/packaging/` has the installer scripts (`linux/build-appimage.sh`, `windows/music.iss`).

```bash
git tag v1.0.0 && git push origin v1.0.0
```

Android builds are signed with the key in the `MUSIC_KEYSTORE_BASE64` / `MUSIC_KEYSTORE_PASSWORD` repo secrets, so updates install over older versions. Local builds read `~/.config/music-signing/key.properties`. Keep a backup of that keystore. Without it, a future update can't install over the existing app.

Each release is also the apt repository (`deb https://github.com/v3ai/music/releases/latest/download ./`). Its index is signed with the key in the `APT_SIGNING_KEY` secret, whose public half is [`site/apt.gpg`](site/apt.gpg). The private key lives in `~/.config/music-signing/apt-gnupg`. Back it up too: with a new key, existing installs stop updating until they re-run the installer. After a release, the `check-apt` job installs from the repository on clean Ubuntu and Debian machines and checks that the app starts.

## Keyboard shortcuts (desktop)

| key | |
|---|---|
| `Space` | play / pause |
| `Shift` + `←` `→` | previous / next |
| `←` `→` | seek 5s |
| `Shift` + `↑` `↓` | volume |
| `/` or `Ctrl`+`K` | search |
| `L` | like current song |
| `S` / `R` | shuffle / repeat |
| `Q` | queue |
| `T` | tabs & chords |
| `Esc` | close now playing |

Right-click any song for its menu.

## Notes

- iPhone isn't supported: Apple only allows App Store apps, and app stores don't allow apps like this.
- For personal use. Respect the terms of the services you use and the rights of artists.
- The earlier browser + server version is kept in git history at the `web-server` tag.
