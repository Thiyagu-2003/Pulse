# Pulse — Improvements

Working list of improvements, ordered by value-per-effort. Small items first.
Each item is implemented, verified with `flutter analyze` + `flutter test`, and
checked off here before the next one starts.

**Verification note:** this machine has no Android SDK, so everything below is
verified by static analysis and unit tests only. Items marked 📱 change runtime
playback behaviour and still need a real device to confirm end to end.

---

## In progress

_(nothing — next up is item 7, album/artist browsing and local artwork)_

## Done

- [x] **Download verified against live YouTube** — `tool/verify_download.dart`
  exercises the real extraction and download path outside Flutter
  (`youtube_explode_dart` is pure Dart, so no device is needed). Run it with
  `dart run tool/verify_download.dart` whenever online playback starts
  misbehaving; YouTube breaks extractors regularly and this says which half is
  at fault in about ten seconds.
  <br>Result: **downloads work, and are audio-only.** 401 KB pulled in under a
  second, container MP4/M4A, magic bytes `…66 74 79 70` (`ftyp`) matching the
  `.m4a` extension.
  <br>It also confirmed the mislabelling bug was real rather than theoretical:
  on the test video the naive highest-bitrate pick is **WebM/Opus at 133 Kbit/s**,
  which the old code wrote to a `.m4a` file. Pulse now picks the 127 Kbit/s
  MP4/AAC stream — marginally lower bitrate, but decodable on iOS and
  honestly named.

- [x] **Online search was completely broken** 📱 — found by the same tool.
  `youtube_explode_dart`'s search parser no longer matches YouTube's response
  and throws `NoSuchMethodError ... getT<String>("text")` inside its own
  `search_page.dart`. `searchMusic` caught it and returned `[]`, so **the whole
  Online tab — search and trending — silently showed "No results found"**.
  3.1.0 is the latest release (published 2026-05-09), so there was no upgrade
  to take.
  <br>Search now goes through NewPipe's native `SearchExtractor` first, which
  is the same extractor already preferred for streams, and filters out Shorts.
  youtube_explode stays as the fallback for non-Android platforms and for
  whenever upstream fixes the parser.
  <br>Verified only as far as compiling: NewPipe is an Android-native
  extractor, so unlike the download path it can't be exercised from the Dart
  VM. It needs a device.

- [x] **Five bugs from a code sweep**
  1. **Crash:** `PlayingIndicator` read `MediaQuery` in `initState`, which
     trips the "dependOnInheritedWidgetOfExactType before initState completed"
     assertion — it would have blown up on the first playing track. Moved to
     `didChangeDependencies`, which also picks up the accessibility setting
     changing at runtime.
  2. **Swiping between Library tabs never rebuilt the app bar**, so the "+"
     button and the sort control stayed wrong until something else triggered a
     rebuild. Only `onTap` called `setState`.
  3. **A `FutureBuilder` created its future inside `build`**, so every
     rebuild re-stat'd every downloaded file on disk. Now recomputed only when
     the download count changes.
  4. **`_visibleSongs` re-filtered and re-sorted the whole library on every
     access**, twice per frame. Cached against its inputs.
  5. **The playlist create/rename dialog leaked a `TextEditingController`**
     every time it opened.

- [x] **Visual refresh** 📱 — grounded in the app's own mark rather than a new
  palette invented from nothing. `icons/app_icon.svg` uses the plate `#13141B`,
  a violet waveform `#7A5CFF→#B57DFF`, and a teal beat-dot `#22D3EE`; the theme
  was using a bluer `#0B0D17` and a harsher neon `#00E5FF`, so **the app didn't
  look like its own icon**. It does now.
  <br>The rule that gives the palette meaning: **teal is the pulse.** In the
  mark it's the dot riding the waveform, so in the UI it marks only what is
  currently sounding. Violet is for things you can press. Previously the accent
  was sprayed on every icon, which made it decoration instead of signal.
  <br>Material 3 `NavigationBar` (sliding selection pill) replaces
  `BottomNavigationBar`. Type scale, sheets, dialogs, sliders, chips, snackbars
  and tab strips now come from the theme instead of hardcoded sizes and
  `Colors.white54` scattered through screens.
  <br>**Motion is deliberate, not sprinkled.** Everything responds to an
  action: play/pause morphs via `AnimatedIcon` (shared `PlayPauseButton` so
  both players behave the same), the favourite heart scales in as it fills,
  row selection glides, the play button's glow swells while sounding,
  artwork/lyrics cross-fade. Explicitly *not* added: fade-and-slide-up
  entrances on every list item, which is the generic default and reads as
  filler.
  <br>The one piece of continuous motion is `PlayingIndicator` — three bars on
  the artwork of the track you can hear. It earns the exception by carrying
  information (which row is live, and whether it's paused) rather than
  decorating, it's literally the pulse the app is named for, and it respects
  the system "remove animations" setting.

- [x] **Video mode fixed** 📱 — three real defects:
  1. **Sync ran off `playbackState`**, which fires only on state changes. A
     steadily playing track produces almost none, so the picture drifted from
     the sound with nothing to correct it, and a seek wasn't followed until
     some unrelated event happened to fire. Now driven by `positionStream`,
     which ticks several times a second — drift is corrected continuously and
     seeks are picked up within ~1.5s.
  2. **`autoPlay: true` regardless of audio state**, so enabling video while
     paused set the picture moving on its own. It now matches the audio and
     starts at the current position.
  3. **A 16:9 player forced into the square artwork frame**, which
     letterboxed it. A 16:9 box is now scaled to cover, cropping the sides so
     the video fills the frame.
  <br>The muted-video-over-separate-audio split is kept deliberately: it's
  what lets background playback and the notification keep working. The cost is
  that sync has to be maintained, which is what the above does.

- [x] **Playback start latency** (from your "takes time when I click a song"
  report). Five causes, biggest first:
  1. **The provider notified listeners on every `playbackState` event.** Those
     fire many times a second while buffering — exactly when you tap — and
     each one rebuilt every visible `TrackTile` *and all four tabs*, since the
     `IndexedStack` keeps them alive. Removed: everything needing live state
     already uses a `StreamBuilder`. This was the big one.
  2. **`stop()` before every track.** On Android that releases the ExoPlayer
     instance `setAudioSource` then has to rebuild, costing a platform round
     trip per tap. Now `pause()`, which is immediate.
  3. **Lyrics were fetched on every track change**, putting an HTTP request on
     the wire at the exact moment the stream URL was being resolved. Now
     fetched only when the lyrics panel is opened.
  4. **Extraction waited out NewPipe's full 10s timeout** before starting the
     fallback, so a failure cost 10s before anything else was tried. NewPipe
     now gets a 3s head start alone, then races the still-running attempt
     against youtube_explode via `firstSuccess` — which, unlike `Future.any`,
     doesn't let a fast failure beat a slower success. 7 tests.
  5. **The next track is now prefetched** while the current one plays, so
     pressing next doesn't pay extraction cost from scratch. `QueueState`
     gained `peekNext`, tested to agree with what `advance` actually plays.
  <br>📱 All five are runtime behaviour — the reasoning is sound and the code
  is tested, but only a device will show the actual milliseconds saved.

- [x] **9. Separate downloads store** — downloads moved out of the favorites
  box into their own, with a Downloads tab, swipe-to-delete, and total size on
  disk. They were conflated before: "do I like this" and "is this on disk" are
  different questions, and a download owns a file that has to be deleted with
  it (deleting the entry alone leaked the bytes forever).
  <br>**Downloaded tracks now actually play from disk** — `playTrack` swaps in
  the local copy — which is the entire point of downloading and did not happen
  before. Instant, offline, and immune to expired stream URLs.
  <br>Real progress replaces the indeterminate spinner: the file is written
  chunk by chunk instead of piped, throttled to repaint per percent rather
  than per chunk. The button shows downloaded state and removes on tap.
  <br>**Not migrated:** downloads made before this change are still sitting in
  favorites as local entries. They'll keep working; they just won't appear
  under Downloads.

- [x] **5. Editable queue** — reorder by drag handle, remove, plus "Play next"
  and "Add to queue" from a long-press on any track tile.
  <br>**The queue was extracted into `lib/models/queue_state.dart` first.** The
  bookkeeping — a queue plus a play order of indices into it, both of which
  every edit has to keep in step — was spread across the provider and so could
  not be tested at all, because the provider needs a live AudioService and
  Hive. `QueueState` needs neither. It carries an `isConsistent` invariant (the
  order is a permutation of the queue's indices and the cursors agree) that
  every test asserts after every operation, including a long mixed sequence of
  edits.
  <br>Uses `onReorderItem`, not the `onReorder` deprecated after Flutter
  3.41 — the new callback applies the drag off-by-one itself, so doing it by
  hand as well would double-count.
  <br>34 tests across `queue_state_test.dart` and `queue_order_test.dart`.

- [x] **6. Real playlists** — create, rename, delete (with confirmation, since
  it can't be undone), add, remove, play all. New Playlists tab in Library, a
  detail screen with swipe-to-remove, and "Add to playlist" in the track
  long-press sheet.
  <br>Playlists store **whole tracks, not ids**: a YouTube search result
  belongs to no local library, so there'd be nothing to join back to.
  Re-adding a track already present is a no-op rather than a duplicate.
  <br>9 tests in `playlist_test.dart`.

- [x] **8. Search and sort** — a shared `TrackFilterBar` on Local and Library.
  Sort by title / artist / album / longest, with artist and album falling back
  to title so a group comes out in a readable order.
  <br>History gets search but **no sort** — it's chronological, and reordering
  it destroys the only thing it means.
  <br>"Play All" queues what's on screen, not the whole library, so a search
  result doesn't wander off into unfiltered songs.
  <br>13 tests in `track_query_test.dart`, including that sorting never
  reorders the caller's list.

- [x] **Local folders** (from your recordings report) — the media store returns
  voice memos and call recordings in one flat list with your music. The Local
  tab now groups by containing folder, which is how the recorder apps already
  separate them on disk. Recording folders are detected by name, sorted below
  music and given a mic icon; a folder opens to its own track list that queues
  only itself, so a call recording can't run on into the next one. Toggle in
  the app bar switches back to a flat list; searching stays flat, since a
  search is looking for a track rather than a folder.
  <br>Nothing is ever hidden — one person's voice memos are another's field
  recordings — and a test asserts no track is dropped by the grouping.
  <br>13 tests in `media_folder_test.dart`.

- [x] **4. Resume position** 📱 — a `positions` Hive box keyed by track id,
  written every 5 seconds of playback (`positionStream` ticks several times a
  second, so it is throttled) and cleared when a track finishes, so a completed
  episode doesn't resume at its own outro.
  <br>Resuming is applied via just_audio's `initialPosition` on the audio
  source rather than a seek afterwards, which would race the asynchronous
  source loading.
  <br>**Scoped to podcasts on purpose.** Dropping back into a 90-minute episode
  where you left off is the expectation; a song you just tapped should start
  from the top. Widening it to long local files is a one-line change in
  `_resumePositionFor`.
  <br>The "is this worth resuming from" rule is a pure function
  (`shouldResume`) with 5 tests covering the near-start, near-end, unknown- and
  zero-duration cases. `flutter analyze` clean, 17 tests pass.

- [x] **3. Sleep timer** — `startSleepTimer` / `cancelSleepTimer` /
  `sleepTimeRemaining` on the provider, driven by a plain `Timer` that pauses
  playback when it fires. Starting a new timer cancels the running one, so two
  can't fire at once, and the provider cancels it in `dispose`.
  <br>UI is a moon button in the shuffle/repeat row opening a sheet with
  5/15/30/45/60-minute options plus Cancel; the button turns accent while a
  timer is live.
  <br>Deliberately skipped: "stop at end of track", and a live countdown on the
  button (that needs a per-second ticker rebuilding the screen). The sheet
  shows the remaining time when opened. Add either if you actually miss it.
  <br>`flutter analyze` clean, 12 tests pass. No unit test — it's a `Timer` and
  a `pause()` call, and faking time to assert on it would be more machinery
  than logic.

- [x] **2. Shuffle + repeat** — an explicit play order (a list of queue
  indices, since item 5 living in `QueueState`) instead of modulo arithmetic on
  the queue, so shuffle is a permutation of that order rather than random
  jumping. Toggling shuffle pins the current track to the front so it doesn't
  yank you off the song you're listening to.
  <br>The decision itself lives in `lib/models/playback_mode.dart` as pure
  functions with no Flutter or plugin imports, so it is unit tested directly —
  no AudioService or Hive needed. 9 cases cover both ends of the list under
  each repeat mode.
  <br>Note the enum is `QueueRepeat`, not `RepeatMode`: Flutter's
  `material.dart` already exports a `RepeatMode` and the collision is a
  compile error.
  <br>**Loop-one uses just_audio's own `LoopMode.one`**, not a replay on
  completion. The first cut reloaded the source every repeat — `stop()`,
  re-resolve the stream URL, re-buffer — which gave an audible gap each loop
  and would eventually fail outright once a YouTube URL expired mid-loop.
  ExoPlayer/AVPlayer loop the source themselves, gaplessly. The handler
  re-asserts the loop mode after each source swap so it survives a track
  change. The `auto && repeat == one` branch in `nextPosition` is kept as a
  fallback for the case where the platform loop doesn't take.
  <br>Both toggles show a 1.2s SnackBar naming the new mode, since tooltips
  only appear on long-press on touch devices — tapping would otherwise change
  nothing visible but the icon.
  <br>`flutter analyze` clean, 12 tests pass.

- [x] **1. Surface playback failures** 📱 — `CustomAudioHandler` now exposes an
  `errors` stream, and the four duplicated "silently reset to idle" blocks in
  `playAppMediaItem` collapsed into one `_failPlayback()` that resets state
  *and* reports. `MainNavigationScreen` subscribes and shows a SnackBar; it is
  the one widget guaranteed to be mounted whenever playback fails, since it
  outlives every tab and the Now Playing route.
  <br>`flutter analyze` clean. Needs a device to confirm the message actually
  appears on a real extraction failure.

## Queued — medium

- [ ] **7. Album/artist browsing + local artwork** — `LocalMusicService` never
  sets `artUri`, so every local song shows the generic note icon despite art
  being embedded in the files. `on_audio_query` provides `QueryArtworkWidget`,
  `queryAlbums` and `queryArtists`.

- [ ] **10. Synced lyrics that scroll** — LRCLIB already returns `syncedLyrics`
  with `[mm:ss.xx]` cues, which are currently stripped for display. Parsing them
  and highlighting the active line against `positionStream` is free data.

## Queued — large

- [ ] **11. Gapless playback** — every track change does `_player.stop()` then
  `setAudioSource`, giving a hard cut and a fresh buffer. Moving to
  `ConcatenatingAudioSource` with the next track preloaded gives gapless
  playback *and* makes `audio_service`'s native queue work, which in turn
  enables Android Auto (`MediaBrowserService` is already declared in the
  manifest but nothing implements `getChildren`).
- [ ] **12. Equalizer** — `just_audio` supports `AndroidEqualizer` and
  `AndroidLoudnessEnhancer` via `AudioPipeline`.

## Known risks (decisions, not tasks)

- **YouTube extraction is a single point of failure.** NewPipe and
  `youtube_explode` break whenever YouTube changes its player. Item 1 makes the
  breakage visible; it does not make it less likely.
- **Distribution.** Downloading YouTube audio breaches YouTube's ToS and will
  not survive Play Store review. The local and podcast halves are unaffected.
  Jamendo, Audius and Free Music Archive offer licensed catalogues with open
  APIs if the YouTube path ever needs replacing.
