import 'package:flutter/material.dart';
import 'package:audio_service/audio_service.dart';
import 'package:just_audio/just_audio.dart';
import '../models/media_item_model.dart';
import 'youtube_service.dart';

Future<AudioHandler> initAudioService() async {
  return await AudioService.init(
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
        skipToNext();
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
      queueIndex: _player.currentIndex,
    ));
  }

  /// Play a specific AppMediaItem with fast non-blocking startup
  Future<void> playAppMediaItem(AppMediaItem item) async {
    String? uri = item.streamUrl;

    // Immediately broadcast the mediaItem so the UI updates with track info
    mediaItem.add(item.toAudioServiceMediaItem());

    // Set state to loading immediately
    playbackState.add(playbackState.value.copyWith(
      processingState: AudioProcessingState.loading,
      playing: true,
    ));

    try {
      // Stop any current playback first
      await _player.stop();

      // Extract stream URL for YouTube tracks if not already cached/resolved
      if (item.sourceType == MediaSourceType.youtube && (uri == null || !uri.startsWith('http'))) {
        try {
          uri = await _ytService.getAudioStreamUrl(item.id);
        } catch (e) {
          debugPrint('YouTube stream extraction failed: $e');
          // Set error state and return
          playbackState.add(playbackState.value.copyWith(
            processingState: AudioProcessingState.idle,
            playing: false,
          ));
          return;
        }
      }

      if (uri == null || uri.isEmpty) {
        debugPrint('No valid URI found for track: ${item.title}');
        playbackState.add(playbackState.value.copyWith(
          processingState: AudioProcessingState.idle,
          playing: false,
        ));
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
        );
      } else if (item.sourceType == MediaSourceType.local && !uri.startsWith('http')) {
        // Local file path
        await _player.setFilePath(uri);
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
        );
      }

      // Start playback immediately — don't await, fire and forget
      _player.play();
    } catch (e) {
      debugPrint('Error playing track: $e');
      // Reset to idle state on error so UI doesn't get stuck on loading
      playbackState.add(playbackState.value.copyWith(
        processingState: AudioProcessingState.idle,
        playing: false,
      ));
    }
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
  Future<void> seek(Duration position) => _player.seek(position);

  @override
  Future<void> setSpeed(double speed) => _player.setSpeed(speed);

  AudioPlayer get player => _player;
}
