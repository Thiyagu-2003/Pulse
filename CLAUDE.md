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
flutter test                 # single file: flutter test test/widget_test.dart
flutter build apk --release  # signed with the debug key; no release signing config yet
dart run flutter_launcher_icons   # regenerate launcher icons from icons/dark_logo.png
```

`test/media_item_model_test.dart` covers the `AppMediaItem` round-trips. Widget tests of the app shell need a `MusicPlayerProvider` (and therefore an initialized `AudioService` and Hive) above them, so prefer testing models and services directly.

## Architecture

Three layers, wired in [main.dart](lib/main.dart): `StorageService.init()` (Hive) → `initAudioService()` (audio_service isolate/service) → a single `ChangeNotifierProvider<MusicPlayerProvider>` over the whole app.

**Everything is an `AppMediaItem`** ([models/media_item_model.dart](lib/models/media_item_model.dart)). Local songs, YouTube results and podcast episodes are all normalized into it, tagged with a `MediaSourceType`. It round-trips through `audio_service`'s `MediaItem` by stuffing `sourceType` and `streamUrl` into `extras` — if you add a field that must survive playback, it has to go into `extras` and into `fromAudioServiceMediaItem`, or it is lost the moment a track plays.

**`CustomAudioHandler`** ([services/audio_handler.dart](lib/services/audio_handler.dart)) owns the single `just_audio` player and is the only place that talks to it. `playAppMediaItem` resolves a URI per source type: `content://` and local paths go straight to the player, YouTube ids are resolved lazily through `YoutubeService`, podcast/HTTP URLs get a desktop-Chrome `User-Agent` (some CDNs reject the default). It broadcasts `mediaItem` and a loading `playbackState` *before* resolving, so the UI updates instantly; failures reset to idle rather than throwing.

**`MusicPlayerProvider`** ([providers/music_player_provider.dart](lib/providers/music_player_provider.dart)) is the only thing the UI touches. It owns the queue and `_currentIndex` and re-broadcasts the handler's streams as `notifyListeners()`. The queue lives *here*, not in `audio_service`'s `QueueHandler`, which is never populated — so the handler exposes `onSkipNext` / `onSkipPrevious` / `onTrackCompleted` callbacks that the provider registers in its constructor, and every control path (notification shade, headset buttons, end of track) advances this one queue. Completion deliberately uses its own callback so it stops at the end of the queue while the skip button wraps.

Seek bars must use `provider.positionStream` (the player's own ticking stream), **not** `PlaybackState.position` — `playbackState` is only broadcast when something changes, so a bar driven by it freezes between events.

**YouTube extraction** ([services/youtube_service.dart](lib/services/youtube_service.dart)) is a fallback chain: in-memory cache (URLs expire after 30 min, hence `_CachedStream`) → `newpipeextractor_dart` (native, Android-only, fast) → `youtube_explode_dart` (slow, most reliable). `YoutubeService` is a singleton — the handler, the provider and the search screen all construct one, and separate instances would mean the screen's prefetched URLs never reach the handler that plays them. For the same reason it has no `dispose()`; closing the shared `YoutubeExplode` would break extraction app-wide. Search uses `youtube_explode` for metadata only. Top 3 search results are prefetched in the background. Downloads always use `youtube_explode` and land in the app documents dir.

Other services are stateless HTTP: [podcast_service.dart](lib/services/podcast_service.dart) (iTunes Search API + hand-rolled RSS parsing via `xml`, episode ids are `audioUrl.hashCode`), [lyrics_service.dart](lib/services/lyrics_service.dart) (LRCLIB, exact match then search fallback; strips "Official Video"-style noise from titles first).

**Persistence** is Hive boxes of JSON strings keyed by track id ([storage_service.dart](lib/services/storage_service.dart)) — no Hive adapters, no codegen. The `playlists` box is opened but unused; the Library tab shows favorites and history only. Downloaded tracks are recorded by writing a `local`-sourced copy into favorites.

**UI** is a four-tab `IndexedStack` ([main_navigation_screen.dart](lib/ui/screens/main_navigation_screen.dart)) with a `MiniPlayer` floated above the nav bar that pushes `NowPlayingScreen`. Colors and fonts come from [app_theme.dart](lib/ui/theme/app_theme.dart) (dark only) and frosted panels from `GlassContainer`.

Video mode in [now_playing_screen.dart](lib/ui/screens/now_playing_screen.dart) is a second, muted `youtube_player_flutter` controller displayed over the audio player and re-synced from `playbackState` whenever it drifts >2s. Audio always comes from `just_audio`; the video player is picture only.

## Android specifics

- `minSdk`/`compileSdk` come from the Flutter defaults; core library desugaring is **required** by `newpipeextractor_dart` and is enabled in [android/app/build.gradle.kts](android/app/build.gradle.kts).
- The manifest declares the `audio_service` foreground service and media-button receiver by hand; `mediaPlayback` foreground type, `POST_NOTIFICATIONS` and `READ_MEDIA_AUDIO` must stay.
- Cleartext traffic is enabled globally — some podcast feeds and extracted stream hosts are still http.
- `LocalMusicService.requestPermission()` asks for `Permission.audio` first (Android 13+) and falls back to `Permission.storage`.
