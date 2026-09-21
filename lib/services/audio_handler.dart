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
      androidNotificationChannelId: 'com.antigravity.musicplayer.channel.audio',
      androidNotificationChannelName: 'Music Player Playback',
      androidNotificationOngoing: true,
      androidStopForegroundOnPause: true,
      androidNotificationIcon: 'mipmap/ic_launcher',
    ),
  );
}

class CustomAudioHandler extends BaseAudioHandler with QueueHandler, SeekHandler {
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

  bool _loopOne = false;

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
    final playing = _player.playing;
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
      }[_player.processingState]!,
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

      // Extract stream URL for YouTube tracks if not already cached/resolved
      if (item.sourceType == MediaSourceType.youtube && (uri == null || !uri.startsWith('http'))) {
        try {
          uri = await _ytService.getAudioStreamUrl(item.id);
        } catch (e) {
          _failPlayback('Couldn\'t load "${item.title}". Tap to try again.', e);
          return;
        }
      }

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
      } else if (item.sourceType == MediaSourceType.local && !uri.startsWith('http')) {
        // Local file path
        await _player.setFilePath(uri, initialPosition: startAt);
      } else {
        // HTTP stream (YouTube, podcast, etc.)
        await _player.setAudioSource(
          AudioSource.uri(
            Uri.parse(uri),
            headers: {
              'User-Agent':
                  'Mozilla/5.0 (Linux; Android 14) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Mobile Safari/537.36',
            },
          ),
          preload: true,
          initialPosition: startAt,
        );
      }

      // Re-assert looping: it must outlive the source swap so the next track
      // keeps looping too.
      await _player.setLoopMode(_loopOne ? LoopMode.one : LoopMode.off);

      // Start playback immediately — don't await, fire and forget
      _player.play();
    } catch (e) {
      _failPlayback('Couldn\'t play "${item.title}". Tap to try again.', e);
    }
  }

  /// Reset to idle so the UI doesn't hang on "loading", and tell the user.
  void _failPlayback(String userMessage, [Object? cause]) {
    if (cause != null) debugPrint('Playback failed: $cause');
    playbackState.add(playbackState.value.copyWith(
      processingState: AudioProcessingState.idle,
      playing: false,
    ));
    _errors.add(userMessage);
  }

  @override
  Future<void> play() => _player.play();

  @override
  Future<void> pause() => _player.pause();

  @override
  Future<void> stop() async {
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
