# music

An ad-free music player for desktop and phone, powered by YouTube Music (via [`ytmusicapi`](https://github.com/sigma67/ytmusicapi)) and [`yt-dlp`](https://github.com/yt-dlp/yt-dlp).

It looks and feels like a normal streaming app: home feed, search, albums, artists, playlists, Liked Songs, queue, shuffle/repeat, lyrics, downloads. It keeps playing when you leave the app or lock your phone, with lock-screen and notification controls.

## How it works

```
 phone / desktop  ──►  music server (this repo, runs on your computer)  ──►  YouTube Music
 (installable web app)   • search / albums / artists via ytmusicapi
                         • audio via yt-dlp, streamed through the server
                         • your library (likes, playlists) in SQLite
                         • downloads saved as tagged .m4a files with cover art
```

- **No ads, no account.** Nothing is sent to Google except anonymous search/stream requests.
- **Fast.** No build step or framework. The app shell is cached by a service worker, so it opens instantly. The next song in the queue is resolved ahead of time, so skipping is near-instant.
- **Plays in the background.** It uses a real `<audio>` element plus the Media Session API. On iOS and Android you get lock-screen and notification controls, artwork, and next/previous, and music keeps playing with the screen off or while you use other apps.
- **Album art everywhere.** Covers load through your server, which keeps a copy on disk, so they show up instantly and never hit Google's rate limits. Music videos get their album's cover: the server finds the matching album song on YouTube Music.
- **Downloads** go two places. The server saves them to `data/downloads/Artist/Artist - Title [id].m4a` with tags and embedded art. On a phone or other remote device they're also stored in the browser, so they play with no connection.

## Run it

Requirements: Python 3.10+ and `ffmpeg` (for tagging downloads).

```bash
git clone https://github.com/v3ai/music && cd music
./music
```

The first run creates a virtualenv and installs everything, including `yt-dlp` and a `deno` JS runtime that yt-dlp needs for YouTube. After that it prints:

```
  music is running
  ▸ this computer: http://localhost:8484
  ▸ phone (same wifi): http://192.168.1.20:8484
```

Other commands:

| command | |
|---|---|
| `./music update` | update yt-dlp and other dependencies (also happens automatically once a day) |
| `./music service` | run in the background and start on login (Linux/systemd). Run `loginctl enable-linger $USER` to keep it running when logged out |

Settings (environment variables):

| variable | default | |
|---|---|---|
| `MUSIC_PORT` | `8484` | |
| `MUSIC_HOST` | `0.0.0.0` | use `127.0.0.1` to only allow this computer |
| `MUSIC_DATA` | `./data` | library database and caches |
| `MUSIC_DOWNLOADS` | `./data/downloads` | where downloaded songs go, e.g. `~/Music` |
| `MUSIC_LANG` / `MUSIC_REGION` | `en` / auto | language and country for search and the home feed |
| `MUSIC_ALLOWED_ORIGINS` | `https://v3ai.github.io` | other sites allowed to use this server, e.g. the GitHub Pages copy of the app |

## Install as an app

**Desktop (Chrome / Edge / Brave):** open `http://localhost:8484` and click the install icon in the address bar. It gets its own window, dock/taskbar icon, and media keys.

**Phone:** the phone needs to reach the computer running the server.

- **Easiest (same Wi-Fi):** open the `phone` URL the server prints. On iPhone, tap Share → *Add to Home Screen*. On Android, use ⋮ → *Add to Home screen*.
- **Recommended (anywhere, with HTTPS):** install [Tailscale](https://tailscale.com) on the computer and phone, then run `tailscale serve --bg 8484` on the computer. Open the `https://<computer>.<tailnet>.ts.net` URL on your phone and add it to your home screen. HTTPS turns on the full app experience: offline downloads on the phone, the install prompt on Android, and instant start-up. It also works away from home.

> Browsers only allow offline storage (service workers) on HTTPS or `localhost`. Over plain `http://192.168…` everything works, including background playback, except saving songs onto the phone itself.

## Use it from GitHub Pages

The app is also published at **https://v3ai.github.io/music/**, redeployed on every push to `main`. It opens straight into the app and connects to your server by itself. If the server isn't running, it still opens and plays your downloaded songs, then connects as soon as the server is up.

How it finds the server, in order:

1. An address set under **Settings** (optional).
2. The repo variable **`MUSIC_SERVER_URL`** (*Settings → Secrets and variables → Actions → Variables*), built into the site on deploy. Set it to an HTTPS address for your server, e.g. from Tailscale (`tailscale serve --bg 8484` → `https://my-computer.tailnet.ts.net`). Your phone then connects with nothing to enter.
3. The server on the same computer (`http://localhost:8484`, desktop only). Chrome asks once to allow access to your local network.

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

Right-click any song for its menu.

## Project layout

```
server/            Python (FastAPI)
  main.py          HTTP API + streaming proxy + static files
  ytm.py           YouTube Music metadata, normalized
  media.py         yt-dlp stream resolving, download worker
  db.py            SQLite library
web/               the app (plain ES modules, no build step) — also deployed to GitHub Pages
  index.html  css/app.css  sw.js  manifest.webmanifest
  js/config.js     which server to talk to (same origin, or the one entered on GitHub Pages)
  js/main.js       router, player UI, now playing, queue
  js/views.js      pages: home, search, album, artist, playlists, library
  js/player.js     playback engine, queue, media session
  js/state.js      API client, library state, downloads
  js/ui.js         icons + components
```

## Notes

- If songs stop playing one day, YouTube changed something. Run `./music update`.
- This is for personal use. Respect the terms of the services you use and the rights of artists.
