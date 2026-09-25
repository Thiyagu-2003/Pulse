# Pulse backend (YouTube era, up to 2026-09-25)

How Pulse listed, played and downloaded online songs before the switch to
JioSaavn. The code described here is backed up unchanged in
[`backup/youtube_backend_2026-09-25/`](../backup/youtube_backend_2026-09-25/);
the YouTube path itself stays in the app for songs saved before the switch
(favorites, history, playlists, downloads) and for video mode.

Everything runs on the phone. There is no Pulse server; each source below is
called directly from the app.

---

## Sources at a glance

| What | Source | Library / endpoint | Auth |
| --- | --- | --- | --- |
| Online songs — search, home rows | YouTube | `newpipeextractor_dart` (native Android), `youtube_explode_dart` fallback | none |
| Search suggestions | YouTube | NewPipe `getSearchSuggestions`, explode `getQuerySuggestions` | none |
| Stream URLs | YouTube (googlevideo CDN) | youtube_explode `getManifest` (clients `androidSdkless`, `android`, watch page), NewPipe `getStream` | none |
| Downloads | YouTube (googlevideo CDN) | youtube_explode stream client, NewPipe URL + HTTP | none |
| Lyrics | LRCLIB | `https://lrclib.net/api/get`, `/api/search` | none |
| Podcasts | Apple iTunes + RSS | `https://itunes.apple.com/search?media=podcast`, each feed's RSS | none |
| Local songs | Android MediaStore | `on_audio_query_plus_android` (patched copy in `third_party/`) | `READ_MEDIA_AUDIO` |

---

## Listing (Online tab)

Code: [`lib/services/youtube_service.dart`](../lib/services/youtube_service.dart),
[`lib/models/home_sections.dart`](../lib/models/home_sections.dart),
[`lib/ui/screens/online_music_screen.dart`](../lib/ui/screens/online_music_screen.dart).

- **Home page:** every row and playlist card is a *YouTube search query*
  (for example `"Tamil hit songs lyric video"`). "lyric video" steers results
  to single songs instead of hour-long compilations.
- **Search:** NewPipe `SearchExtractor.searchYoutube` first (12 s timeout).
  youtube_explode's search is the fallback: its parser breaks often, and after
  a burst of requests YouTube answers with redirect loops.
- **`cachedSearch`** (home page): results are memoized per query, saved in the
  `search_cache` Hive box (shown instantly on launch, refreshed after 2 h,
  pruned after 24 h), at most 3 searches at a time, and one retry on an empty
  result.
- **Suggestions:** YouTube's autocomplete, debounced 250 ms; the top 4 matching
  songs appear after 700 ms.
- Results carry **no playable URL**. Every tap needs a separate lookup.

## Playing

Code: [`lib/services/audio_handler.dart`](../lib/services/audio_handler.dart),
`YoutubeService.getAudioStreamUrl`, [`lib/services/playback_cache.dart`](../lib/services/playback_cache.dart).

1. A **saved copy** in the playback cache plays instantly
   (`<id>_<id>.*` files, 400 MB cap, least recently played removed first).
2. Otherwise a **stream URL** is looked up:
   - Cache keyed `<videoId>@<quality>`, in memory and in the `stream_urls` box.
     Expiry is read from the URL's `expire=` parameter (about 6 h).
   - Uncached: the youtube_explode `androidSdkless` and `android` clients race
     (about 200–350 ms). Then the watch-page path, then NewPipe.
3. The URL plays through just_audio's **local proxy** (Dart HTTP client) with
   `LockCachingAudioSource`, which saves the song while it streams (Wi-Fi only).
4. If the player fails on a URL: a checked URL from each *other* source, then
   **download the whole song and play the file**. Each attempt times out after
   10 s.
5. Quality: Data saver (lowest bitrate), Balanced (AAC ~128 kbps), Best (Opus
   ~160 kbps). Data saver is forced on mobile data when that setting is on.

**Known limits:** googlevideo URLs expire, need a lookup per song, and are
intermittently refused (403) for unauthenticated clients. That made first
starts slow or failed on real phones, which is why the Online source moved to
JioSaavn.

## Downloading

Code: `YoutubeService.downloadAudioTrack`, `_downloadViaExplode`,
`_downloadViaNewPipe`, `_writeAudioFile`.

- youtube_explode first (AAC in MP4 at the best bitrate), NewPipe fallback.
- Written to `<name>.<size>.part`, renamed when complete, with a 20 s idle
  timeout. An interrupted download **resumes** with an HTTP Range request.
- File name: `Title - Artist [id].m4a`, cut to 180 UTF-8 bytes.
- Saved to the custom folder if writable, else the app's Music folder.
- A `dataSync` foreground service keeps the app alive while downloads run.
  Progress shows as a system notification.

## Lyrics

Code: [`lib/services/lyrics_service.dart`](../lib/services/lyrics_service.dart).
LRCLIB `api/get?track_name=&artist_name=` exact match, then `api/search?q=`.
Titles are cleaned of "(Official Video)", "Lyric Video", "HD" and similar
noise first. Synced lyrics are stripped to plain text.

## Podcasts

Code: [`lib/services/podcast_service.dart`](../lib/services/podcast_service.dart).
iTunes Search API for channels, then each channel's RSS feed parsed with
`xml` (decoded as UTF-8). Episode audio URLs are played directly.

## Storage (Hive, `hive_ce`)

Boxes of JSON strings keyed by id: `favorites`, `history`, `playlists`,
`downloads`, `positions`, `settings`, plus the caches `stream_urls`,
`search_cache` and `playback_log`. See
[`lib/services/storage_service.dart`](../lib/services/storage_service.dart).
