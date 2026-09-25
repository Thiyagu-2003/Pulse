# Backend API

What Karadify talks to, for listing and for playing. Everything here is
verifiable against the code — file references are given throughout, and the
probe scripts in `tool/` hit the live API.

---

## One host

Listing and playback both come from JioSaavn's private web API:

```
https://www.jiosaavn.com/api.php
  ?__call=<endpoint>
  &_format=json&_marker=0&api_version=4&ctx=web6dot0
```

No API key, no account, no token exchange.

Every request carries one header that matters:

```
Cookie: L=tamil
```

That is what makes the home shelves Tamil. Without it the feed is Hindi by
default — measured on `new_trending`: **hindi:19** with no cookie, **tamil:20**
with `L=tamil`. The value follows the Home language setting.

Transport lives in [`lib/services/saavn/saavn_api.dart`](lib/services/saavn/saavn_api.dart),
and everything above it in [`lib/services/saavn/saavn_service.dart`](lib/services/saavn/saavn_service.dart).

---

## Listing

| Screen | Endpoint | Notes |
| --- | --- | --- |
| Home shelves | `webapi.getLaunchData` | `new_trending`, `top_playlists`, `new_albums`, `charts` |
| "Trending in Tamil" | `content.getTrending` | `entity_type=song`, `entity_language=tamil` |
| Curated rows | `search.getResults` | one call per row, batched five at a time |
| Search — All | `autocomplete.get` + `search.getResults` + `search.getAlbumResults` | three calls in parallel |
| Search — Songs | `search.getResults` | |
| Search — Albums | `search.getAlbumResults` | |
| Search — Playlists | `search.getPlaylistResults` | |
| Search — Artists | `autocomplete.get` | |
| Album page | `content.getAlbumDetails` | `albumid` |
| Playlist page | `playlist.getDetails` | `listid`, `n=100` |
| Artist page | `artist.getArtistPageDetails` | `artistId` |
| Re-fetch a saved song | `song.getDetails` | `pids`, used when a song restored from disk has no media url |

### Why "All" makes three calls

`autocomplete.get` returns every category in one response, but its song rows
carry **no media url** and it only ever returns three albums. So songs come from
`search.getResults` and albums from `search.getAlbumResults`, with autocomplete
supplying artists and playlists. The three run concurrently.

### Film names vs. song names

Searching a film name should surface its soundtrack; searching a song name
should surface songs. Both are just text, so the discriminator is **track
count** on the first album whose title matches:

```
Leo              → album "Leo", 7 tracks    → soundtrack, lead with Albums
Ordinary Person  → album "Ordinary Person", 1 track → a single, lead with Songs
```

Only the *first* title match is considered. Results are relevance-ordered, and
scanning past it finds coincidences — "Ordinary Person" also matches an
unrelated 9-track album further down, which otherwise hijacked the result.

Measured: 6/6 film names, 3/4 song names, 3/3 artist names. The miss is
*Why This Kolaveri Di*, which genuinely does have a multi-track release under
that exact name.

Re-run it: `dart run tool/probe_topkind.dart`

---

## Playing

Search results already carry the playable URL, DES-encrypted:

```
more_info.encrypted_media_url
        │
        │  DES-ECB, key "38346591"   (long-public, not something we discovered)
        ▼
https://aac.saavncdn.com/323/7b0f4cf0f773cff9514e9913312610b7_96.mp4
        │
        │  swap the bitrate suffix
        ▼
…_320.mp4          → handed to ExoPlayer as a plain AudioSource.uri
```

Bitrate follows Settings → Audio quality: `_96`, `_160`, `_320`.

### Two details worth knowing

**PointyCastle ships no single-DES**, only 3DES. Triple-DES with the same key in
all three slots reduces to single DES, so the 8-byte key is simply repeated to
24 bytes. See `SaavnApi.decryptMediaUrl`.

**The CDN urls carry no expiry token.** That is why the decrypted url is cached
on the `Song` model and persists in Hive, and why playback is a plain
`AudioSource.uri` — no chunking, no local proxy, no custom headers.

---

## Not JioSaavn

**Lyrics** come from [LRCLIB](https://lrclib.net) at `https://lrclib.net/api` —
free, open, unauthenticated, and independent of the audio source. Time-synced
where available, plain text otherwise.
See [`lib/services/lyrics/lyrics_service.dart`](lib/services/lyrics/lyrics_service.dart).

---

## Defensive parsing

JioSaavn is loosely typed: a field that is a list on one response comes back as
a string on the next. A hard `as List?` then takes down the whole page with

```
type 'String' is not a subtype of type 'List<dynamic>?' in type cast
```

which is exactly what happened on the album and playlist screens. Every access
now goes through:

```dart
static List? _list(dynamic v) => v is List ? v : null;
static Map?  _map (dynamic v) => v is Map  ? v : null;
```

The top-level responses are guarded the same way — `album()`, `playlist()`,
`artist()`, `home()` and `search()` all assumed a Map and would have thrown
identically if handed a List.

Verified by opening 29 real album / playlist / artist pages across five
searches, 0 failures: `dart run tool/probe_collections.dart`

---

## Checking it still works

All of these hit the live API from a PC, no phone needed, and answer in seconds
— which tells a network problem apart from a parser problem:

```powershell
dart run tool/verify_search.dart "leo"    # search, playback, curated rows, home
dart run tool/probe_saavn.dart "aaluma"   # DES decrypt + whole-file fetch
dart run tool/probe_collections.dart      # album / playlist / artist pages
dart run tool/probe_topkind.dart          # film vs song vs artist detection
```

`verify_search.dart` is the one to run first. It ends with a playback check that
fetches bytes from the 80% mark of each file — the exact request the previous
YouTube backend always refused.

---

## Why JioSaavn and not YouTube

YouTube serves roughly the **first 20%** of an audio file to an unauthenticated
client and answers 403 to every byte range past that. It is fixed when the URL
is issued; no client-side change moves it. That was measured exhaustively before
switching — see [FINDINGS.md](FINDINGS.md).

JioSaavn serves whole files, at up to 320 kbps, with no account, and its
catalogue is Indian film music, which is what this app is for.

---

## Legal position

This is JioSaavn's **private** web API, not a published one. Same category as
the YouTube API this replaced: outside their Terms of Service, written for
personal and educational use, not something to put on an app store or
distribute commercially.

The practical difference from YouTube is that JioSaavn does not actively defend
it — which is why this works and the YouTube path did not. That could change,
and if it does, the probe scripts above will say so in seconds.
