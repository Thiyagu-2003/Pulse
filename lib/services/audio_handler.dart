import 'dart:async';

import 'package:flutter/material.dart';
import 'package:audio_service/audio_service.dart';
import 'package:just_audio/just_audio.dart';
import '../models/media_item_model.dart';
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

class CustomAudioHandler extends BaseAudioHandler with QueueHandler, SeekHandler {
  // Streams go through just_audio's local proxy, i.e. Dart's HTTP client —
  // the same stack that checks and downloads use, which works reliably.
  // Letting ExoPlayer fetch googlevideo directly was tried and songs then
  // often failed to play on real phones, while downloads kept working.
  final AudioPlayer _player = AudioPlayer();
  final YoutubeService _ytService = YoutubeService();

  /// The queue lives in MusicPlayerProvider, not in audio_service's QueueHandler.
  /// It registers these so notification buttons, headset keys and track
  /// completion all advance the same queue the UI shows.
  VoidCallback? onSkipNext;
  VoidCallback? onSkipPrevious;

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
    playbackState.add(playbackState.value.copyWith(
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
    ));
  }

  /// Play a specific AppMediaItem with fast non-blocking startup.
  ///
  /// [startAt] is applied as the source's initial position rather than a seek
  /// after the fact, which would race the asynchronous source loading.
  Future<void> playAppMediaItem(AppMediaItem item, {Duration? startAt}) async {
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
    playbackState.add(playbackState.value.copyWith(
      processingState: AudioProcessingState.loading,
      playing: true,
    ));

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
      final cachedFile = item.sourceType == MediaSourceType.youtube
          ? await _ytService.cachedPlaybackPath(item.id)
          : null;
      if (superseded()) return;

      if (cachedFile != null) {
        uri = cachedFile;
      } else if (item.sourceType == MediaSourceType.youtube) {
        try {
          uri = await _ytService.getAudioStreamUrl(item.id);
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

      // Update the mediaItem with resolved stream URL
      final updatedItem = AppMediaItem(
        id: item.id,
        title: item.title,
        artist: item.artist,
        album: item.album,
        artUri: item.artUri,
        streamUrl: uri,
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
        await _player.setFilePath(uri, initialPosition: startAt);
      } else {
        // HTTP stream (YouTube, podcast, etc.)
        // A stalled load counts as failed after 10s, so the fallbacks get a
        // turn instead of the song spinning indefinitely. (The next load
        // interrupts the stalled one.)
        Future<void> load(String url) => _player
            .setAudioSource(
              AudioSource.uri(
                Uri.parse(url),
                headers: {
                  'User-Agent':
                      'Mozilla/5.0 (Linux; Android 14) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Mobile Safari/537.36',
                },
              ),
              preload: true,
              initialPosition: startAt,
            )
            .timeout(const Duration(seconds: 10));
        if (item.sourceType == MediaSourceType.youtube) {
          await _loadYoutube(item, uri, load, superseded, startAt);
        } else {
          await load(uri);
        }
      }

      // Re-assert looping: it must outlive the source swap so the next track
      // keeps looping too.
      await _player.setLoopMode(_loopOne ? LoopMode.one : LoopMode.off);

      // Checked right before play(): no await may sit between this and it.
      if (superseded()) return;

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
        lastError = e;
        return false;
      }
    }

    if (await attempt(first)) return;
    _ytService.invalidateStreamUrl(item.id);

    await for (final url
        in _ytService.alternativeStreamUrls(item.id, exclude: tried)) {
      if (superseded()) return;
      if (await attempt(url)) return;
    }
    if (superseded()) return;

    debugPrint('No stream would play for ${item.id}; fetching the file');
    final path = await _ytService.cacheForPlayback(item);
    if (superseded()) return;
    if (path == null) throw lastError ?? StateError('no playable source');
    await _player.setFilePath(path, initialPosition: startAt);
  }

  /// Reset to idle so the UI doesn't hang on "loading", and tell the user.
  void _failPlayback(String userMessage, [Object? cause]) {
    if (cause != null) debugPrint('Playback failed: $cause');
    _loading = false;
    // The previous track's source is still loaded (we only paused it), so
    // without this, Play would resume the old audio under the new title.
    _player.stop();
    playbackState.add(playbackState.value.copyWith(
      processingState: AudioProcessingState.idle,
      playing: false,
    ));
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
