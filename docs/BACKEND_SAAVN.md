# Pulse backend: JioSaavn (from 2026-09-25)

How Pulse lists, plays, downloads and finds lyrics for online songs since the
switch from YouTube. The previous backend is described in
[BACKEND_YOUTUBE.md](BACKEND_YOUTUBE.md) and backed up in
[`backup/youtube_backend_2026-09-25/`](../backup/youtube_backend_2026-09-25/).
The original proposal is [`New proposed api.md`](../New%20proposed%20api.md).

Code: [`lib/services/saavn_service.dart`](../lib/services/saavn_service.dart),
wired in through `YoutubeService.catalog` / `searchMusic`, the audio handler's
`_loadSaavn`, and `YoutubeService._downloadSaavn`.

---

## One host, one cookie

```
GET https://www.jiosaavn.com/api.php
      ?__call=<endpoint>&_format=json&_marker=0&api_version=4&ctx=web6dot0&…
Cookie: L=<home language, lowercase>     e.g. L=tamil
```

No key, no account. The cookie picks the feed language and follows
Settings → Home language. With "no language rows" the cookie is `L=hindi,english`.

## Endpoints used

| Purpose | Endpoint | Parameters |
| --- | --- | --- |
| Song search (search screen, fallback rows) | `search.getResults` | `q`, `p=1`, `n=30` |
| "Trending in <language>" row | `content.getTrending` | `entity_type=song`, `entity_language` |
| Home rows and cards | `search.getPlaylistResults` → `playlist.getDetails` | `q`, then `listid`, `n=50` |
| Search suggestions | `autocomplete.get` | `query` |
| Lyrics | `lyrics.getLyrics` | `lyrics_id=<song id>` |
| Re-fetch one song | `song.getDetails` | `pids` |

Home rows are *editorial playlists* (`playlist:Love Tamil` → JioSaavn's "Sad
Love - Tamil", 50 songs). Measured: every Tamil row 16–50 songs, all Tamil.
Across Tamil, Hindi, Telugu and Malayalam, playlists came back 20–50 songs
almost entirely in the right language, where a plain artist search mixed
languages (for example "Anirudh": 10 of 20 Tamil). A name with no playlist
falls back to a song search. See [`home_sections.dart`](../lib/models/home_sections.dart).

## Playing

Every listed song already carries its URL, so a tap needs no lookup:

```
more_info.encrypted_media_url
   │  base64 → DES-ECB, key "38346591" (PointyCastle 3DES with the key ×3)
   ▼
https://aac.saavncdn.com/…/<hash>_96.mp4
   │  bitrate from Settings → Audio quality: _96 / _160 / _320
   │  (Data saver on mobile data forces _96)
   ▼
player
```

- CDN URLs **don't expire** and are saved on the song (favorites and
  playlists keep working).
- The file is served whole: byte ranges answer 206 from any point, including
  80% in, at every bitrate.
- The load order is: saved copy (instant) → through Dart with
  `LockCachingAudioSource` (saved while it plays, Wi-Fi only) → direct
  ExoPlayer → a fresh link from `song.getDetails`.

## Downloading

A plain HTTP file: 320 kbps, falling back to 160. Written as
`<file>.<size>.part` and renamed when complete. An interrupted download
resumes with a Range request. Measured: a 10 MB song in about 1.1 s from a PC,
and a resumed download ends byte-identical.

## Lyrics

For a JioSaavn song, `lyrics.getLyrics` by song id first (about 110 ms;
`<br>` becomes a newline). Then [LRCLIB](https://lrclib.net): exact match with
all artists, then with the first artist only (JioSaavn lists "A, B, C";
LRCLIB usually has just "A"), then a search.

## Defensive parsing

JioSaavn is loosely typed: a field can be a list in one response and a string
in the next. Every access goes through `_list` / `_map` / `_str`, never a hard
cast, and non-song or URL-less entries are skipped. Titles are HTML-unescaped
(`&quot;` → `"`).

## What stays on YouTube

- Songs saved before the switch (their `sourceType` is `youtube`).
- The search fallback when JioSaavn returns nothing.
- Video mode.

## Checking it still works

```powershell
dart run tool/probe_saavn.dart "vaseegara"   # search, decrypt, bytes at 0% and 80%
flutter test test_live                       # everything above, through the app's code
```

## Legal position

This is JioSaavn's **private** web API: undocumented and outside their terms,
like the YouTube path before it. It's for personal use only, not for an app
store or commercial distribution, and it can change without notice. The probe
above detects that in seconds.
