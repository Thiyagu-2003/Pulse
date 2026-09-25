# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project

Pulse — a Flutter music/podcast player that unifies local device audio, YouTube audio streams, and RSS podcasts behind one player. Android is the primary target (NewPipe extraction is native Android); iOS/web/desktop folders exist but are unexercised.

The pubspec package name is `music_player`, so internal imports are `package:music_player/...` even though the app is called Pulse.

## Commands

```bash
flutter pub get
flutter run                  # attach an Android 13+ device
flutter analyze              # lint (flutter_lints)
flutter test                 # unit + widget tests in test/ (no network)
flutter test test_live       # real YouTube/iTunes/LRCLIB calls through the app's services
flutter build apk --release  # signed with the debug key; no release signing config yet
dart run flutter_launcher_icons   # regenerate launcher icons from icons/dark_logo.png
```

Widget tests build the real app shell (see [test/app_flow_test.dart](test/app_flow_test.dart)): `Hive.init` on a temp dir, a real `MusicPlayerProvider(CustomAudioHandler(), StorageService())`, and search results seeded through `YoutubeService().seedSearch`. Two traps: seed futures *inside* the test body (a future completed outside the fake-async zone never delivers inside it), and don't trigger Hive writes from taps and then `Hive.deleteFromDisk` in teardown — the write can't finish in the fake zone and teardown hangs; drive settings through the provider inside `tester.runAsync` instead. `YoutubeService` exposes `@visibleForTesting` overrides (`debugExtractOverride`, `debugSearchOverride`, `debugSuggestionsOverride`) so its caching/queueing logic is tested without the network.

## Architecture

Three layers, wired in [main.dart](lib/main.dart): `StorageService.init()` (Hive) → `initAudioService()` (audio_service isolate/service) → a single `ChangeNotifierProvider<MusicPlayerProvider>` over the whole app. `MaterialApp` takes `themeMode` from the provider.

**Everything is an `AppMediaItem`** ([models/media_item_model.dart](lib/models/media_item_model.dart)). Local songs, YouTube results and podcast episodes are all normalized into it, tagged with a `MediaSourceType`. It round-trips through `audio_service`'s `MediaItem` by stuffing `sourceType` and `streamUrl` into `extras` — if you add a field that must survive playback, it has to go into `extras` and into `fromAudioServiceMediaItem`, or it is lost the moment a track plays.

**`CustomAudioHandler`** ([services/audio_handler.dart](lib/services/audio_handler.dart)) owns the single `just_audio` player and is the only place that talks to it.
- `playAppMediaItem` broadcasts `mediaItem` and a loading state *before* resolving. A `_loadGeneration` counter makes a slower, older load give way to a newer tap. While `_loading`, the player still holds the previous (paused) source, so `_broadcastState` reports loading and `play()`/`pause()` only set intent — never forward them to the player there, or Play resumes the old song under the new title.
- YouTube tracks: playback-cache file first (instant), else a stream URL, then `_loadYoutube` falls back through `alternativeStreamUrls` (a checked URL from each *other* source) and finally `cacheForPlayback` (download the whole song, play the file). Each attempt times out after 10s.
- Streams go through just_audio's local proxy (the default `AudioPlayer()`), i.e. Dart's HTTP client. Letting ExoPlayer fetch googlevideo directly (`useProxyForRequestHeaders: false`) broke playback on real phones while desktop probes looked fine — don't switch it back without device logs.
- `play()` reloads the current item when the player is idle (after Stop or a failure), asking the provider's `resumePositionFor` for a podcast position. `clear()` stops and forgets the item when the queue is emptied.

**`MusicPlayerProvider`** ([providers/music_player_provider.dart](lib/providers/music_player_provider.dart)) is the only thing the UI touches. The queue is a [`QueueState`](lib/models/queue_state.dart) (display order + a play-order permutation for shuffle, no duplicate tracks) — *not* audio_service's `QueueHandler`, which is never populated. The handler exposes `onSkipNext` / `onSkipPrevious` / `onTrackCompleted` callbacks the provider registers, so notification, headset, widget and end-of-track all advance this one queue; completion stops at the end while the skip button wraps. Repeat-one is the player's own `LoopMode.one`. `_play` prefers a downloaded file only if it still exists, and writes the *online* track to history. It also pushes now-playing state to the home-screen widget and runs downloads (with system notifications).

Seek bars must use `provider.positionStream` (the player's own ticking stream), **not** `PlaybackState.position` — `playbackState` is only broadcast when something changes, so a bar driven by it freezes between events. Play/pause UI should read `playbackState.value.playing` (the handler's view), not `player.playing`.

**YouTube** ([services/youtube_service.dart](lib/services/youtube_service.dart)) is a singleton — the handler, provider and screens must share one, or prefetched URLs never reach the handler that plays them. It has no `dispose()`; closing the shared `YoutubeExplode` would break extraction app-wide.
- Stream URLs: in-memory cache (30 min expiry) → `_inFlight` dedupe → race of youtube_explode's `androidSdkless` and `android` clients (both with `requireWatchPage: false`, ~1s faster than the watch-page path) → watch-page path → NewPipe. The in-flight `whenComplete` must use a block body: `=> map.remove(key)` returns the same future and awaits itself forever.
- Search: NewPipe first (youtube_explode's search parser is unreliable; it's the fallback). `cachedSearch` (home page) memoizes per query, runs at most 3 at once and retries an empty result once — bursts get redirect-looped by YouTube. Search screen prefetches the first 8 results' URLs; suggestions via `searchSuggestions`.
- Downloads: youtube_explode first, NewPipe fallback, written via `.part` + rename with a 20s idle timeout, into the custom folder (probed for writability) or the app's music dir.

Other services are stateless HTTP: [podcast_service.dart](lib/services/podcast_service.dart) (iTunes Search API + hand-rolled RSS parsing via `xml`, decoded as UTF-8; episode ids are `audioUrl.hashCode`), [lyrics_service.dart](lib/services/lyrics_service.dart) (LRCLIB, exact match then search fallback; `cleanQuery` strips "Official Video"-style noise as whole words).

**Persistence** is Hive boxes of JSON strings keyed by track id ([storage_service.dart](lib/services/storage_service.dart)) — no adapters, no codegen: favorites, history (each entry stamped with `playedAt` — Hive keeps keys *sorted*, not in insertion order), playlists, downloads (the on-disk copy of a track), podcast positions, and settings (home language, audio quality, theme, launcher icon, recent searches, download folder).

**UI** is a four-tab `IndexedStack` ([main_navigation_screen.dart](lib/ui/screens/main_navigation_screen.dart)) — Online home, Local, Podcasts, Library — with a `MiniPlayer` above the nav bar that pushes `NowPlayingScreen`. The Online tab ([online_music_screen.dart](lib/ui/screens/online_music_screen.dart)) is built from [home_sections.dart](lib/models/home_sections.dart): every row/card is a YouTube search query ("lyric video" in a query keeps results to single songs). Colours: light and dark themes in [app_theme.dart](lib/ui/theme/app_theme.dart); screens read neutrals as `context.colors.*` (a `ThemeExtension`). The `AppTheme.*` constants are the dark palette, used only where the surface is dark in both themes — Now Playing, whose route is wrapped in `Theme(AppTheme.darkTheme)`.

Video mode in [now_playing_screen.dart](lib/ui/screens/now_playing_screen.dart) is a second, muted `youtube_player_flutter` controller shown over the artwork, re-synced to the audio position (and speed) when it drifts. Turning it off disposes the controller. Audio always comes from `just_audio`; the video player is picture only.

## Android specifics

- `minSdk`/`compileSdk` come from the Flutter defaults; core library desugaring is **required** (NewPipe, flutter_local_notifications) and is enabled in [android/app/build.gradle.kts](android/app/build.gradle.kts). Minify/shrink are off, so `proguard-rules.pro` is currently unused.
- The manifest declares the `audio_service` foreground service and media-button receiver by hand; `mediaPlayback` foreground type, `POST_NOTIFICATIONS` and `READ_MEDIA_AUDIO` must stay.
- The launcher entry is two `activity-alias`es (light/dark icon); `MainActivity.setLauncherIcon` swaps them, applied only when the app goes to the background.
- `MainActivity` hosts the `pulse/platform` channel ([platform_bridge.dart](lib/services/platform_bridge.dart)): widget updates and the icon switch. The home-screen widget is `PulseWidgetProvider`; its buttons go through `PulseWidgetActionReceiver` to audio_service's `MediaButtonReceiver` while the app runs, and open the app when it doesn't (`MainActivity.engineReady`).
- `on_audio_query_plus_android` is a patched copy in [third_party/](third_party/on_audio_query_plus_android) (`dependency_overrides`); see its `PULSE PATCH` comments. The upstream version crashed with "Reply already submitted" right after the audio permission was granted. Don't call its `permissionsRequest`/`scan`; permissions go through `permission_handler`.
- Cleartext traffic is enabled globally — some podcast feeds are still http.
- `LocalMusicService.requestPermission()` asks for `Permission.audio` first (Android 13+), falls back to `Permission.storage`, and opens app settings from the "Grant Access" button once permanently denied.
