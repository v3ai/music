# music

An ad-free music player for **Android, Windows, macOS and Linux**, powered by YouTube Music.

**Download: https://v3ai.github.io/music/**

It looks and works like a normal streaming app: home feed, search, albums, artists, playlists, Liked Songs, queue, shuffle and repeat, lyrics, guitar tabs, and downloads. Music keeps playing with the screen off or the app in the background, with lock-screen, notification and headphone controls.

- **No ads, no account, no server.** The app talks to YouTube Music directly from your device.
- **Album art everywhere.** Music videos show the cover of the album their song is on.
- **Downloads** are stored inside the app, so they play with no connection.
- **Your library** (likes, playlists, saved albums and artists) lives on your device.
- **Autoplay** keeps playing similar songs when your queue ends.
- **Guitar and bass tabs** (from [Songsterr](https://www.songsterr.com)) that scroll along with the song. Tap a bar to jump there, pick another part from the menu, and nudge the timing with − / + if it's off. Most well-known songs have one.

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
flutter build windows       # Windows
flutter build macos         # macOS
```

`source tool/env.sh` sets up `PATH` if Flutter and the Android SDK live in `~/development/flutter` and `~/Android/Sdk`.

## Releasing

Push a tag to build every platform on GitHub Actions and publish a release. The download page always points at the latest one.

```bash
git tag v1.0.0 && git push origin v1.0.0
```

Android builds are signed with the key in the `MUSIC_KEYSTORE_BASE64` / `MUSIC_KEYSTORE_PASSWORD` repo secrets, so updates install over older versions. Local builds read `~/.config/music-signing/key.properties`. Keep a backup of that keystore. Without it, a future update can't install over the existing app.

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
| `T` | guitar tabs |
| `Esc` | close now playing |

Right-click any song for its menu.

## Notes

- iPhone isn't supported: Apple only allows App Store apps, and app stores don't allow apps like this.
- For personal use. Respect the terms of the services you use and the rights of artists.
- The earlier browser + server version is kept in git history at the `web-server` tag.
