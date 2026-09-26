import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:audio_service/audio_service.dart';
import 'package:just_audio/just_audio.dart';
import '../models/media_item_model.dart';
import 'network_status.dart';
import 'playback_cache.dart';
import 'playback_log.dart';
import 'saavn_service.dart';
import 'storage_service.dart' show AudioQuality;
import 'youtube_service.dart';

Future<CustomAudioHandler> initAudioService() async {
  return await AudioService.init<CustomAudioHandler>(
    builder: () => CustomAudioHandler(),
    config: const AudioServiceConfig(
      androidNotificationChannelId: 'com.pulse.music.channel.audio',
      androidNotificationChannelName: 'Music Player Playback',
      androidNotificationOngoing: true,
      androidStopForegroundOnPause: true,
      // Status-bar icons are drawn from alpha only; the full-colour launcher
      // PNG showed as a white square.
      androidNotificationIcon: 'drawable/ic_stat_pulse',
    ),
  );
}

class CustomAudioHandler extends BaseAudioHandler
    with QueueHandler, SeekHandler {
  // Streams go through just_audio's local proxy, i.e. Dart's HTTP client —
  // the same stack that checks and downloads use, which works reliably.
  // Letting ExoPlayer fetch googlevideo directly was tried and songs then
  // often failed to play on real phones, while downloads kept working.
  // Start after 1s of audio instead of ExoPlayer's 2.5s: noticeably
  // quicker on a weak signal, at a small risk of an early stall.
  late final AudioPlayer _player = AudioPlayer(
    useProxyForRequestHeaders: !Platform.isWindows,
    audioLoadConfiguration: const AudioLoadConfiguration(
      androidLoadControl: AndroidLoadControl(
        bufferForPlaybackDuration: Duration(milliseconds: 1000),
      ),
    ),
    // Settings > Equalizer. Android only; elsewhere these do nothing.
    audioPipeline: AudioPipeline(androidAudioEffects: [equalizer, loudness]),
  );

  final AndroidEqualizer equalizer = AndroidEqualizer();
  final AndroidLoudnessEnhancer loudness = AndroidLoudnessEnhancer();
  final YoutubeService _ytService = YoutubeService();

  /// The queue lives in MusicPlayerProvider, not in audio_service's QueueHandler.
  /// It registers these so notification buttons, headset keys and track
  /// completion all advance the same queue the UI shows.
  VoidCallback? onSkipNext;
  VoidCallback? onSkipPrevious;

  /// Android Auto: the provider answers browsing and plays what's picked
  /// (the handler has no library of its own).
  Future<List<MediaItem>> Function(String parentMediaId)? onBrowse;
  Future<void> Function(String mediaId)? onPlayFromMediaId;

  @override
  Future<List<MediaItem>> getChildren(
    String parentMediaId, [
    Map<String, dynamic>? options,
  ]) async => await onBrowse?.call(parentMediaId) ?? const [];

  @override
  Future<void> playFromMediaId(
    String mediaId, [
    Map<String, dynamic>? extras,
  ]) async => onPlayFromMediaId?.call(mediaId);

  /// Separate from [onSkipNext] so end-of-track advance can stop at the end of
  /// the queue while the skip button still wraps around.
  VoidCallback? onTrackCompleted;

  /// Where to start a track reloaded by [play] (after Stop or a failure);
  /// the provider answers with the saved podcast position.
  Duration? Function(AppMediaItem track)? resumePositionFor;

  bool _loopOne = false;
  int _loadGeneration = 0;

  /// True from a tap until the new track starts (or fails). Meanwhile the
  /// player still holds the *previous* source, paused — so its events must
  /// not be broadcast as-is, or the UI shows the new title as "paused,
  /// ready" and Play resumes the old song under it.
  bool _loading = false;

  /// Pause pressed while loading: honoured by not starting playback.
  bool _pauseRequested = false;

  /// Loop the current track at the player level. ExoPlayer/AVPlayer repeat the
  /// source themselves, which is gapless and — unlike replaying on completion
  /// — never re-resolves the stream URL, so a looping YouTube track can't die
  /// when its extracted URL expires mid-loop.
  Future<void> setLoopOne(bool enabled) async {
    _loopOne = enabled;
    await _player.setLoopMode(enabled ? LoopMode.one : LoopMode.off);
  }

  final StreamController<String> _errors = StreamController<String>.broadcast();

  /// User-facing playback failures. Extraction breaks often enough (YouTube
  /// changes its player) that failing silently just looks like a dead app.
  Stream<String> get errors => _errors.stream;

  CustomAudioHandler() {
    _initPlayerListeners();
  }

  void _initPlayerListeners() {
    // Broadcast playback state updates instantly to UI, notification shade & lockscreen
    _player.playbackEventStream.listen((PlaybackEvent event) {
      _broadcastState();
    });

    // Also listen to playing state changes for immediate UI response
    _player.playingStream.listen((_) {
      _broadcastState();
    });

    // Also listen to processing state for loading/buffering transitions
    _player.processingStateStream.listen((state) {
      _broadcastState();
      // Automatically skip to next track when item completes
      if (state == ProcessingState.completed) {
        onTrackCompleted?.call();
      }
    });
  }

  void _broadcastState() {
    final playing = _loading ? !_pauseRequested : _player.playing;
    playbackState.add(
      playbackState.value.copyWith(
        controls: [
          MediaControl.skipToPrevious,
          if (playing) MediaControl.pause else MediaControl.play,
          MediaControl.skipToNext,
          MediaControl.stop,
        ],
        systemActions: const {
          MediaAction.seek,
          MediaAction.seekForward,
          MediaAction.seekBackward,
        },
        androidCompactActionIndices: const [0, 1, 2],
        processingState: const {
          ProcessingState.idle: AudioProcessingState.idle,
          ProcessingState.loading: AudioProcessingState.loading,
          ProcessingState.buffering: AudioProcessingState.buffering,
          ProcessingState.ready: AudioProcessingState.ready,
          ProcessingState.completed: AudioProcessingState.completed,
        }[_loading ? ProcessingState.loading : _player.processingState]!,
        playing: playing,
        updatePosition: _player.position,
        bufferedPosition: _player.bufferedPosition,
        speed: _player.speed,
        // No just_audio playlist is used — one source at a time — so there is no
        // meaningful index into audio_service's (empty) queue.
        queueIndex: null,
      ),
    );
  }

  /// Play a specific AppMediaItem with fast non-blocking startup.
  ///
  /// [startAt] is applied as the source's initial position rather than a seek
  /// after the fact, which would race the asynchronous source loading.
  Future<void> playAppMediaItem(AppMediaItem item, {Duration? startAt}) async {
    final attempt = PlaybackLog.instance.begin(
      item.title,
      item.sourceType.name,
    );
    _attempt = attempt;
    try {
      await _playAppMediaItem(item, startAt, attempt);
    } finally {
      // Still "loading" here means a newer tap took over.
      PlaybackLog.instance.finish(
        attempt,
        attempt.outcome == 'loading' ? 'superseded' : attempt.outcome,
      );
    }
  }

  /// The attempt being loaded, for [_failPlayback] to mark.
  PlaybackAttempt? _attempt;

  Future<void> _playAppMediaItem(
    AppMediaItem item,
    Duration? startAt,
    PlaybackAttempt attempt,
  ) async {
    String? uri = item.streamUrl;
    // Tapping B while A's YouTube URL is still resolving must not let A take
    // over (or report an error) once its resolution finally lands.
    final load = ++_loadGeneration;
    bool superseded() => load != _loadGeneration;
    _loading = true;
    _pauseRequested = false;

    // Immediately broadcast the mediaItem so the UI updates with track info
    mediaItem.add(item.toAudioServiceMediaItem());

    // Set state to loading immediately
    playbackState.add(
      playbackState.value.copyWith(
        processingState: AudioProcessingState.loading,
        playing: true,
      ),
    );

    try {
      // Silence the outgoing track, but don't stop(): on Android that
      // releases the ExoPlayer instance that setAudioSource then has to
      // rebuild, adding a round trip to every single tap. pause() is
      // immediate and setAudioSource replaces the source anyway.
      await _player.pause();

      // Always resolve YouTube through the service, never a URL carried on
      // the item: those expire, so a retry of a track that had played before
      // kept failing on its old link. The service's cache knows when a URL
      // is still fresh.
      // Fetched in full before (see _loadYoutube): play the file, instantly.
      final cachedFile = item.sourceType.isOnline
          ? await PlaybackCache.instance.find(item.id)
          : null;
      if (superseded()) return;

      if (cachedFile != null) {
        uri = cachedFile;
        attempt.step('saved copy on this phone');
      } else if (item.sourceType == MediaSourceType.saavn) {
        // The URL came with the song and doesn't expire; only the bitrate
        // is chosen now (Settings, or Data saver on mobile data).
        uri = item.streamUrl;
        // Anything but a web link (e.g. a temp-file path an older build
        // saved into favorites) means "no link": fetch a fresh one.
        if (uri == null || !uri.startsWith('http')) {
          try {
            uri = (await SaavnService.instance.song(item.id))?.streamUrl;
          } catch (e) {
            uri = null;
            attempt.step('JioSaavn lookup failed: ${e.runtimeType}');
          }
          if (superseded()) return;
        }
        if (uri != null) {
          uri = SaavnService.withQuality(uri, _ytService.playbackQuality());
        }
        attempt.step('JioSaavn link');
      } else if (item.sourceType == MediaSourceType.youtube) {
        try {
          uri = await _ytService.getAudioStreamUrl(item.id);
          attempt.step('link via ${_ytService.lastSource[item.id] ?? 'cache'}');
        } catch (e) {
          if (superseded()) return;
          _failPlayback('Couldn\'t load "${item.title}". Tap to try again.', e);
          return;
        }
      }

      if (superseded()) return;

      if (uri == null || uri.isEmpty) {
        _failPlayback(
          'No playable audio found for "${item.title}".',
          'empty URI for ${item.id}',
        );
        return;
      }

      // Update the mediaItem with resolved stream URL — but never with the
      // saved copy's path: the item is what favorites/playlists/downloads
      // copy, and that temp file can be deleted any time.
      final updatedItem = AppMediaItem(
        id: item.id,
        title: item.title,
        artist: item.artist,
        album: item.album,
        artUri: item.artUri,
        streamUrl: cachedFile != null ? item.streamUrl : uri,
        duration: item.duration,
        sourceType: item.sourceType,
        lyrics: item.lyrics,
        extras: item.extras,
      );
      mediaItem.add(updatedItem.toAudioServiceMediaItem());

      // Set audio source based on URI type
      if (uri.startsWith('content://')) {
        await _player.setAudioSource(
          AudioSource.uri(Uri.parse(uri)),
          preload: true,
          initialPosition: startAt,
        );
      } else if (!uri.startsWith('http')) {
        // Local file path
        try {
          await _player.setFilePath(uri, initialPosition: startAt);
        } catch (e) {
          if (superseded() || cachedFile == null) rethrow;
          // A saved copy that won't play (cut short, corrupt): throw it away
          // and stream instead, or every later tap would fail the same way.
          attempt.step('saved copy unplayable, streaming');
          await PlaybackCache.instance.remove(item.id);
          final url = item.sourceType == MediaSourceType.saavn
              ? await _saavnUrl(item)
              : await _ytService.getAudioStreamUrl(item.id);
          if (superseded()) return;
          if (url == null) rethrow;
          await _player.setAudioSource(
            AudioSource.uri(Uri.parse(url)),
            preload: true,
            initialPosition: startAt,
          );
        }
      } else {
        // HTTP stream (YouTube, podcast, etc.)
        // A stalled load counts as failed after 10s, so the fallbacks get a
        // turn instead of the song spinning indefinitely. (The next load
        // interrupts the stalled one.)
        const headers = {
          'User-Agent':
              'Mozilla/5.0 (Linux; Android 14) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Mobile Safari/537.36',
        };
        Future<void> load(String url) async {
          // YouTube songs are saved while they stream, so a replay starts
          // from disk (PlaybackCache keeps the folder bounded). Both go
          // through Dart's HTTP client, the path that works on real phones.
          // Not on mobile data: a save isn't cancelled when the user skips,
          // so skipping ten songs would download all ten in full.
          // On Windows, LockCachingAudioSource is unsupported by just_audio_windows
          // and headers proxy triggers AppContainer loopback restrictions.
          final save = !Platform.isWindows &&
              item.sourceType.isOnline &&
              !NetworkStatus.instance.onMobileData;
          final AudioSource source = save
              // Experimental in just_audio; if it misbehaves the load
              // fails and the fallback ladder in _loadYoutube takes over.
              // ignore: experimental_member_use
              ? LockCachingAudioSource(
                  Uri.parse(url),
                  headers: headers,
                  cacheFile: await PlaybackCache.instance.streamFileFor(
                    item.id,
                  ),
                )
              : (Platform.isWindows
                  ? AudioSource.uri(Uri.parse(url))
                  : AudioSource.uri(Uri.parse(url), headers: headers));
          await _player
              .setAudioSource(source, preload: true, initialPosition: startAt)
              .timeout(const Duration(seconds: 10));
        }

        if (item.sourceType == MediaSourceType.youtube) {
          await _loadYoutube(item, uri, load, superseded, startAt);
        } else if (item.sourceType == MediaSourceType.saavn) {
          await _loadSaavn(item, uri, load, superseded, startAt);
        } else {
          await load(uri);
        }
      }

      // Re-assert looping: it must outlive the source swap so the next track
      // keeps looping too.
      await _player.setLoopMode(_loopOne ? LoopMode.one : LoopMode.off);

      // Checked right before play(): no await may sit between this and it.
      if (superseded()) return;

      attempt.step('player ready');
      attempt.outcome = 'playing';
      PlaybackCache.instance.playingId = item.id;
      if (item.sourceType.isOnline) {
        PlaybackCache.instance.trim(keep: item.id);
      }
      _loading = false;
      if (_pauseRequested) {
        _broadcastState(); // loaded, but the user paused while waiting
      } else {
        // Start playback immediately — don't await, fire and forget
        _player.play();
      }
    } catch (e) {
      // A newer setAudioSource interrupts this one; that isn't a failure.
      if (superseded()) return;
      _ytService.invalidateStreamUrl(item.id);
      _failPlayback('Couldn\'t play "${item.title}". Tap to try again.', e);
    }
  }

  /// A JioSaavn song's link at the current quality: the one it carries if
  /// that's a web link, else a fresh one.
  Future<String?> _saavnUrl(AppMediaItem item) async {
    var url = item.streamUrl;
    if (url == null || !url.startsWith('http')) {
      url = (await SaavnService.instance.song(item.id))?.streamUrl;
    }
    return url == null
        ? null
        : SaavnService.withQuality(url, _ytService.playbackQuality());
  }

  /// Load a JioSaavn song: through Dart (saved while it plays), then
  /// directly by ExoPlayer the way JioSaavn's own player fetches it, then
  /// with a freshly fetched link in case the saved one went stale.
  Future<void> _loadSaavn(
    AppMediaItem item,
    String url,
    Future<void> Function(String url) load,
    bool Function() superseded,
    Duration? startAt,
  ) async {
    Object? lastError;
    try {
      await load(url);
      return;
    } catch (e) {
      if (superseded()) rethrow;
      lastError = e;
      _attempt?.step('stream failed: ${e.runtimeType}; trying direct');
    }
    try {
      await _player
          .setAudioSource(
            AudioSource.uri(Uri.parse(url)),
            preload: true,
            initialPosition: startAt,
          )
          .timeout(const Duration(seconds: 10));
      return;
    } catch (e) {
      if (superseded()) rethrow;
      lastError = e;
      _attempt?.step('direct failed: ${e.runtimeType}; fresh link');
    }
    final fresh = await SaavnService.instance.song(item.id);
    if (superseded()) return;
    final freshUrl = fresh?.streamUrl;
    if (freshUrl == null) throw lastError;
    try {
      await load(
        SaavnService.withQuality(freshUrl, _ytService.playbackQuality()),
      );
    } catch (e) {
      if (superseded()) rethrow;
      // Last try: the smallest file, which starts on the weakest signal.
      _attempt?.step('fresh link failed; trying 96 kbps');
      await load(SaavnService.withQuality(freshUrl, AudioQuality.dataSaver));
    }
  }

  /// Load a YouTube track, falling back through every alternative before
  /// giving up: the stream URL we were given; then a checked URL from each
  /// *other* source; then fetching the whole song and playing the file.
  Future<void> _loadYoutube(
    AppMediaItem item,
    String first,
    Future<void> Function(String url) load,
    bool Function() superseded,
    Duration? startAt,
  ) async {
    final tried = <String>{};
    Object? lastError;

    Future<bool> attempt(String url) async {
      tried.add(url);
      try {
        await load(url);
        return true;
      } catch (e) {
        if (superseded()) rethrow; // interrupted by a newer tap
        debugPrint('Stream failed for ${item.id}: $e');
        _attempt?.step('stream failed: ${e.runtimeType}');
        lastError = e;
        return false;
      }
    }

    if (await attempt(first)) return;
    _ytService.invalidateStreamUrl(item.id);

    await for (final url in _ytService.alternativeStreamUrls(
      item.id,
      exclude: tried,
    )) {
      if (superseded()) return;
      _attempt?.step(
        'trying ${_ytService.lastSource[item.id] ?? 'alternative'}',
      );
      if (await attempt(url)) return;
    }
    if (superseded()) return;

    debugPrint('No stream would play for ${item.id}; fetching the file');
    _attempt?.step('fetching the whole song');
    final path = await _ytService.cacheForPlayback(item);
    if (superseded()) return;
    if (path == null) throw lastError ?? StateError('no playable source');
    await _player.setFilePath(path, initialPosition: startAt);
  }

  /// Reset to idle so the UI doesn't hang on "loading", and tell the user.
  void _failPlayback(String userMessage, [Object? cause]) {
    if (cause != null) debugPrint('Playback failed: $cause');
    _attempt?.outcome = 'failed';
    _attempt?.step('error: ${cause ?? userMessage}');
    _loading = false;
    // The previous track's source is still loaded (we only paused it), so
    // without this, Play would resume the old audio under the new title.
    _player.stop();
    playbackState.add(
      playbackState.value.copyWith(
        processingState: AudioProcessingState.idle,
        playing: false,
      ),
    );
    _errors.add(userMessage);
  }

  /// Every resume goes through here — the in-app button, the notification,
  /// headset keys. After a failed or stopped load the player may still hold
  /// the *previous* track's source, so plain play() would bring back the old
  /// song under the new title; reload what the UI shows instead.
  @override
  Future<void> play() async {
    if (_loading) {
      // The track being prepared will start by itself; just undo a pause.
      _pauseRequested = false;
      _broadcastState();
      return;
    }
    final current = mediaItem.value;
    // Nothing selected (queue emptied, or nothing played yet): there is no
    // song to resume, and the player may still hold a removed one.
    if (current == null) return;
    if (_player.audioSource == null ||
        _player.processingState == ProcessingState.idle) {
      final track = AppMediaItem.fromAudioServiceMediaItem(current);
      await playAppMediaItem(track, startAt: resumePositionFor?.call(track));
      return;
    }
    // A finished track is parked at its end, where play() does nothing.
    if (_player.processingState == ProcessingState.completed) {
      await _player.seek(Duration.zero);
    }
    await _player.play();
  }

  @override
  Future<void> pause() async {
    if (_loading) {
      _pauseRequested = true;
      _broadcastState();
      return;
    }
    await _player.pause();
  }

  /// Stop and forget the current track (the queue was emptied).
  Future<void> clear() async {
    await stop();
    mediaItem.add(null);
  }

  @override
  Future<void> stop() async {
    // Abandon any load in progress, or the state stays "loading" forever.
    _loadGeneration++;
    _loading = false;
    await _player.stop();
    await super.stop();
  }

  @override
  Future<void> skipToNext() async => onSkipNext?.call();

  @override
  Future<void> skipToPrevious() async => onSkipPrevious?.call();

  @override
  Future<void> seek(Duration position) => _player.seek(position);

  @override
  Future<void> setSpeed(double speed) => _player.setSpeed(speed);

  AudioPlayer get player => _player;
}
