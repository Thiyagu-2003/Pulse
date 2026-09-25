import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:provider/provider.dart';
import 'package:audio_service/audio_service.dart';
import '../../models/media_item_model.dart';
import '../../models/playback_mode.dart';
import '../../providers/music_player_provider.dart';
import '../theme/app_theme.dart';
import '../widgets/glass_container.dart';
import '../widgets/lyrics_view.dart';
import '../widgets/track_tile.dart';
import 'dart:async';
import 'package:youtube_player_flutter/youtube_player_flutter.dart';

class NowPlayingScreen extends StatefulWidget {
  const NowPlayingScreen({super.key});

  @override
  State<NowPlayingScreen> createState() => _NowPlayingScreenState();
}

class _NowPlayingScreenState extends State<NowPlayingScreen> {
  bool _showLyrics = false;
  double? _dragMs;
  bool _isVideoMode = false;
  YoutubePlayerController? _youtubeController;
  StreamSubscription? _playbackSubscription;
  String? _currentVideoId;

  @override
  void dispose() {
    _youtubeController?.dispose();
    _playbackSubscription?.cancel();
    super.dispose();
  }

  /// Video mode shows a muted YouTube player over the artwork while audio
  /// keeps coming from just_audio. That split is what makes background
  /// playback and the notification keep working, but it means the picture has
  /// to be actively kept in step with the sound.
  void _toggleVideoMode(MusicPlayerProvider provider, AppMediaItem track) {
    if (_isVideoMode) {
      _stopVideo();
      return;
    }

    final position = provider.audioHandler.player.position;
    final isPlaying = provider.audioHandler.player.playing;

    if (_youtubeController == null || _currentVideoId != track.id) {
      _youtubeController?.dispose();
      _currentVideoId = track.id;
      _youtubeController = YoutubePlayerController(
        initialVideoId: track.id,
        flags: YoutubePlayerFlags(
          // Match the audio instead of assuming playback: enabling video
          // while paused used to start the picture moving on its own.
          autoPlay: isPlaying,
          startAt: position.inSeconds,
          mute: true, // sound always comes from just_audio
          hideControls: true,
          disableDragSeek: true,
          enableCaption: false,
        ),
      );
    } else {
      _youtubeController!.seekTo(position);
      if (isPlaying) _youtubeController!.play();
    }

    setState(() => _isVideoMode = true);
    _startVideoSync(provider);
  }

  void _startVideoSync(MusicPlayerProvider provider) {
    _playbackSubscription?.cancel();

    // Driven by positionStream, which ticks several times a second. The old
    // code synced only on playbackState events, which are sparse during
    // steady playback — so the picture drifted away from the sound and never
    // followed a seek until some unrelated event happened to fire.
    _playbackSubscription = provider.positionStream.listen((audioPosition) {
      final controller = _youtubeController;
      if (!mounted || !_isVideoMode || controller == null) return;
      if (!controller.value.isReady) return;

      // The picture must run at the audio's speed, or at 1.5x it falls
      // behind and gets re-seeked every couple of seconds.
      final speed = provider.audioHandler.player.speed;
      if (controller.value.playbackRate != speed) {
        controller.setPlaybackRate(speed);
      }

      final isPlaying = provider.audioHandler.player.playing;
      if (isPlaying != controller.value.isPlaying) {
        isPlaying ? controller.play() : controller.pause();
      }
      if (!isPlaying) return;

      final drift = audioPosition - controller.value.position;
      if (drift.abs() > const Duration(milliseconds: 1500)) {
        controller.seekTo(audioPosition);
      }
    });
  }

  /// Leave video mode and throw the controller away. Its player widget is
  /// gone the moment video is hidden, and a kept controller came back from a
  /// fresh widget at its *original* start position and autoplay setting —
  /// the picture restarted at an old point, even with the audio paused.
  void _stopVideo() {
    _stopVideoSync();
    _youtubeController?.dispose();
    _youtubeController = null;
    _currentVideoId = null;
    if (mounted) setState(() => _isVideoMode = false);
  }

  /// Stops the hidden video streaming once it's no longer on screen.
  void _stopVideoSync() {
    _playbackSubscription?.cancel();
    _playbackSubscription = null;
  }

  @override
  Widget build(BuildContext context) {
    final playerProvider = Provider.of<MusicPlayerProvider>(context);
    // Read from the player: it outlives this screen, so a copy in widget
    // state showed "1.0x" on reopen while audio kept playing at 1.5x.
    final playbackSpeed = playerProvider.audioHandler.player.speed;
    final track = playerProvider.currentTrack;

    if (track == null) {
      return Scaffold(
        appBar: AppBar(),
        body: const Center(child: Text('No song selected')),
      );
    }

    if (_currentVideoId != null &&
        _currentVideoId != track.id &&
        _isVideoMode) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          _stopVideoSync();
          setState(() {
            _isVideoMode = false;
            _youtubeController?.pause();
          });
        }
      });
    }

    // With the panel open, a new track needs its lyrics fetched too
    // (the fetch is keyed per track, so this is a no-op otherwise).
    if (_showLyrics) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) playerProvider.ensureLyricsLoaded();
      });
    }

    final isFav = playerProvider.isFavorite(track.id);

    return Scaffold(
      body: Stack(
        children: [
          // Blurred background image
          if (track.artUri != null && track.artUri!.startsWith('http'))
            Positioned.fill(
              child: CachedNetworkImage(
                imageUrl: track.artUri!,
                fit: BoxFit.cover,
              ),
            ),
          Positioned.fill(
            child: BackdropFilter(
              filter: ImageFilter.blur(sigmaX: 40, sigmaY: 40),
              child: Container(color: Colors.black.withValues(alpha: 0.7)),
            ),
          ),

          // Main Player content
          SafeArea(
            child: Column(
              children: [
                // Top Bar
                Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 8,
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      IconButton(
                        icon: const Icon(Icons.keyboard_arrow_down, size: 30),
                        onPressed: () => Navigator.pop(context),
                      ),
                      Expanded(
                        child: Column(
                          children: [
                            Text(
                              track.sourceType.label.toUpperCase(),
                              style: const TextStyle(
                                fontSize: 10,
                                letterSpacing: 2,
                                color: AppTheme.accent,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            Text(
                              track.album,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              textAlign: TextAlign.center,
                              style: const TextStyle(
                                fontSize: 14,
                                color: Colors.white70,
                              ),
                            ),
                          ],
                        ),
                      ),
                      IconButton(
                        icon: Icon(
                          _showLyrics ? Icons.music_note : Icons.lyrics,
                          color: _showLyrics ? AppTheme.accent : Colors.white70,
                        ),
                        onPressed: () {
                          if (!_showLyrics && _isVideoMode) _stopVideo();
                          setState(() {
                            _showLyrics = !_showLyrics;
                          });
                          // Lyrics are fetched on demand, not on every track
                          // change, so ask for them when the panel opens.
                          if (_showLyrics) playerProvider.ensureLyricsLoaded();
                        },
                      ),
                    ],
                  ),
                ),

                const Spacer(),

                // Center Content: Artwork OR Synced Lyrics. Cross-faded so
                // the swap reads as one surface turning over rather than two
                // unrelated panels replacing each other.
                if (_showLyrics)
                  Expanded(
                    flex: 8,
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 24),
                      child: GlassContainer(
                        child: playerProvider.isLoadingLyrics
                            ? const Center(child: CircularProgressIndicator())
                            : playerProvider.currentLyrics == null
                                ? const Center(
                                    child: Text(
                                      'No lyrics found for this song.',
                                      style: TextStyle(color: Colors.white60),
                                    ),
                                  )
                                : LyricsView(
                                    // A new song starts a fresh view.
                                    key: ValueKey(playerProvider.currentLyrics),
                                    lyrics: playerProvider.currentLyrics!,
                                    positions: playerProvider.positionStream,
                                    duration: () =>
                                        playerProvider.currentDuration,
                                    onSeek: playerProvider.audioHandler.seek,
                                  ),
                      ),
                    ),
                  )
                else
                  Stack(
                    alignment: Alignment.bottomRight,
                    children: [
                      Hero(
                        tag: 'artwork_${track.id}',
                        child: Container(
                          // Width-based, but never more than ~40% of the
                          // height: in landscape 75% of the width is taller
                          // than the screen.
                          width: _artSide(context),
                          height: _artSide(context),
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(24),
                            boxShadow: [
                              BoxShadow(
                                color: AppTheme.primary.withValues(alpha: 0.3),
                                blurRadius: 30,
                                spreadRadius: 5,
                              ),
                            ],
                          ),
                          child: ClipRRect(
                            borderRadius: BorderRadius.circular(24),
                            child: _isVideoMode && _youtubeController != null
                                // A 16:9 player dropped straight into this
                                // square frame letterboxed itself. Scaling a
                                // 16:9 box to cover crops the sides instead,
                                // so the video fills the artwork.
                                ? FittedBox(
                                    fit: BoxFit.cover,
                                    clipBehavior: Clip.hardEdge,
                                    child: SizedBox(
                                      width: 640,
                                      height: 360,
                                      child: YoutubePlayer(
                                        controller: _youtubeController!,
                                        showVideoProgressIndicator: false,
                                        aspectRatio: 16 / 9,
                                      ),
                                    ),
                                  )
                                : track.artUri != null &&
                                      track.artUri!.startsWith('http')
                                ? CachedNetworkImage(
                                    imageUrl: track.artUri!,
                                    fit: BoxFit.cover,
                                  )
                                : Container(
                                    color: Colors.white10,
                                    child: const Icon(
                                      Icons.music_note,
                                      size: 100,
                                      color: AppTheme.primary,
                                    ),
                                  ),
                          ),
                        ),
                      ),
                      if (track.sourceType == MediaSourceType.youtube)
                        Padding(
                          padding: const EdgeInsets.all(12.0),
                          child: FloatingActionButton.small(
                            backgroundColor: _isVideoMode
                                ? AppTheme.primary
                                : AppTheme.lift,
                            foregroundColor: AppTheme.mist,
                            elevation: 0,
                            tooltip: _isVideoMode
                                ? 'Show artwork'
                                : 'Show video',
                            onPressed: () =>
                                _toggleVideoMode(playerProvider, track),
                            child: Icon(
                              _isVideoMode
                                  ? Icons.art_track_rounded
                                  : Icons.videocam_rounded,
                              size: 20,
                            ),
                          ),
                        ),
                    ],
                  ),

                const Spacer(),

                // Track Info & Favorite Button
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 24),
                  child: Row(
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              track.title,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                fontSize: 22,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              track.artist,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                fontSize: 16,
                                color: Colors.white60,
                              ),
                            ),
                          ],
                        ),
                      ),
                      // A track played from its download is a local copy of
                      // an online one; show its state so it can be removed.
                      if (track.sourceType.isOnline ||
                          playerProvider.isDownloaded(track.id))
                        DownloadButton(item: track, size: 26),
                      IconButton(
                        icon: Icon(
                          isFav ? Icons.favorite : Icons.favorite_border,
                          color: isFav ? Colors.redAccent : Colors.white70,
                          size: 28,
                        ),
                        onPressed: () => playerProvider.toggleFavorite(track),
                      ),
                    ],
                  ),
                ),

                const SizedBox(height: 16),

                // Seek Progress Bar
                StreamBuilder<Duration>(
                  stream: playerProvider.positionStream,
                  builder: (context, snapshot) {
                    final duration =
                        playerProvider.currentDuration ?? Duration.zero;

                    // Protect against zero/negative duration
                    final maxMs = duration.inMilliseconds.toDouble();
                    final safeDuration = maxMs > 0 ? maxMs : 1.0;
                    // While dragging, follow the thumb rather than the player.
                    final rawPosition =
                        _dragMs ??
                        (snapshot.data ?? Duration.zero).inMilliseconds
                            .toDouble();
                    final safePosition = rawPosition.clamp(0.0, safeDuration);
                    final position = Duration(
                      milliseconds: safePosition.toInt(),
                    );

                    return Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 24),
                      child: Column(
                        children: [
                          SliderTheme(
                            data: SliderTheme.of(context).copyWith(
                              activeTrackColor: AppTheme.primary,
                              inactiveTrackColor: Colors.white24,
                              thumbColor: AppTheme.accent,
                              trackHeight: 4,
                            ),
                            child: Slider(
                              min: 0,
                              max: safeDuration,
                              value: safePosition,
                              // Seek once on release; seeking on every drag
                              // frame floods the player and stutters.
                              onChanged: (val) => setState(() => _dragMs = val),
                              // Hold the thumb where it was dropped until the
                              // seek lands, or it snaps back for a frame.
                              onChangeEnd: (val) async {
                                await playerProvider.audioHandler.seek(
                                  Duration(milliseconds: val.toInt()),
                                );
                                if (mounted) setState(() => _dragMs = null);
                              },
                            ),
                          ),
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Text(
                                _formatDuration(position),
                                style: const TextStyle(
                                  fontSize: 12,
                                  color: Colors.white54,
                                ),
                              ),
                              Text(
                                _formatDuration(duration),
                                style: const TextStyle(
                                  fontSize: 12,
                                  color: Colors.white54,
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    );
                  },
                ),

                // Shuffle / Repeat — kept on their own row so the main
                // transport controls stay large and uncrowded.
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    IconButton(
                      icon: const Icon(Icons.shuffle_rounded, size: 22),
                      color: playerProvider.isShuffled
                          ? AppTheme.accent
                          : Colors.white38,
                      tooltip: playerProvider.isShuffled
                          ? 'Shuffle on'
                          : 'Shuffle off',
                      onPressed: () {
                        playerProvider.toggleShuffle();
                        _toast(
                          playerProvider.isShuffled
                              ? 'Shuffle on'
                              : 'Shuffle off',
                        );
                      },
                    ),
                    const SizedBox(width: 24),
                    IconButton(
                      icon: Icon(
                        playerProvider.repeatMode == QueueRepeat.one
                            ? Icons.repeat_one_rounded
                            : Icons.repeat_rounded,
                        size: 22,
                      ),
                      color: playerProvider.repeatMode == QueueRepeat.off
                          ? Colors.white38
                          : AppTheme.accent,
                      tooltip: switch (playerProvider.repeatMode) {
                        QueueRepeat.off => 'Repeat off',
                        QueueRepeat.all => 'Repeat queue',
                        QueueRepeat.one => 'Repeat track',
                      },
                      onPressed: () {
                        playerProvider.cycleRepeat();
                        _toast(switch (playerProvider.repeatMode) {
                          QueueRepeat.off => 'Repeat off',
                          QueueRepeat.all => 'Repeating queue',
                          QueueRepeat.one => 'Looping this track',
                        });
                      },
                    ),
                    const SizedBox(width: 24),
                    IconButton(
                      icon: const Icon(Icons.bedtime_rounded, size: 22),
                      color: playerProvider.hasSleepTimer
                          ? AppTheme.accent
                          : Colors.white38,
                      tooltip: 'Sleep timer',
                      onPressed: () =>
                          _showSleepTimerSheet(context, playerProvider),
                    ),
                  ],
                ),

                // Playback Control Buttons
                StreamBuilder<PlaybackState>(
                  stream: playerProvider.playbackState,
                  builder: (context, snapshot) {
                    final state = snapshot.data;
                    final playing = state?.playing ?? false;
                    final processingState =
                        state?.processingState ?? AudioProcessingState.idle;
                    final isBuffering =
                        processingState == AudioProcessingState.buffering ||
                        processingState == AudioProcessingState.loading;

                    return Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                        children: [
                          IconButton(
                            icon: Text(
                              '${playbackSpeed}x',
                              style: const TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.bold,
                                color: AppTheme.accent,
                              ),
                            ),
                            onPressed: () async {
                              const speeds = [1.0, 1.25, 1.5, 2.0];
                              final next =
                                  speeds[(speeds.indexOf(playbackSpeed) + 1) %
                                      speeds.length];
                              await playerProvider.audioHandler.setSpeed(next);
                              if (mounted) setState(() {});
                            },
                          ),

                          IconButton(
                            iconSize: 36,
                            icon: const Icon(Icons.skip_previous_rounded),
                            onPressed: playerProvider.skipToPrevious,
                          ),

                          // Floating Play/Pause Action Button with Buffering state
                          GestureDetector(
                            onTap: playerProvider.togglePlayPause,
                            child: AnimatedContainer(
                              duration: const Duration(milliseconds: 220),
                              curve: Curves.easeOut,
                              width: 70,
                              height: 70,
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                gradient: AppTheme.waveGradient,
                                boxShadow: [
                                  // The glow swells while sounding and
                                  // settles when paused — the button itself
                                  // carries the state.
                                  BoxShadow(
                                    color: AppTheme.primary.withValues(
                                      alpha: playing ? 0.55 : 0.25,
                                    ),
                                    blurRadius: playing ? 28 : 14,
                                    spreadRadius: playing ? 2 : 0,
                                  ),
                                ],
                              ),
                              child: isBuffering
                                  ? const Padding(
                                      padding: EdgeInsets.all(22.0),
                                      child: CircularProgressIndicator(
                                        strokeWidth: 2.5,
                                        color: AppTheme.mist,
                                      ),
                                    )
                                  : Icon(
                                      playing
                                          ? Icons.pause_rounded
                                          : Icons.play_arrow_rounded,
                                      size: 38,
                                      color: AppTheme.mist,
                                    ),
                            ),
                          ),

                          IconButton(
                            iconSize: 36,
                            icon: const Icon(Icons.skip_next_rounded),
                            onPressed: playerProvider.skipToNext,
                          ),

                          IconButton(
                            icon: const Icon(
                              Icons.queue_music_rounded,
                              color: Colors.white70,
                            ),
                            onPressed: () {
                              _showQueueBottomSheet(context, playerProvider);
                            },
                          ),
                        ],
                      ),
                    );
                  },
                ),

                const SizedBox(height: 24),
              ],
            ),
          ),
        ],
      ),
    );
  }

  /// Brief confirmation of a mode change. Tooltips only appear on long-press
  /// on touch devices, so a tap would otherwise give no feedback but an icon.
  void _toast(String message) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text(message),
          duration: const Duration(milliseconds: 1200),
          behavior: SnackBarBehavior.floating,
        ),
      );
  }

  void _showSleepTimerSheet(
    BuildContext context,
    MusicPlayerProvider provider,
  ) {
    const options = [
      Duration(minutes: 5),
      Duration(minutes: 15),
      Duration(minutes: 30),
      Duration(minutes: 45),
      Duration(hours: 1),
    ];
    final remaining = provider.sleepTimeRemaining;

    showModalBottomSheet(
      context: context,
      backgroundColor: AppTheme.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (sheetContext) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.all(16),
              child: Text(
                remaining != null
                    ? 'Pausing in ${remaining.inMinutes + 1} min'
                    : 'Sleep timer',
                style: const TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
            for (final option in options)
              ListTile(
                leading: const Icon(
                  Icons.bedtime_outlined,
                  color: Colors.white54,
                ),
                title: Text(
                  option.inMinutes < 60
                      ? '${option.inMinutes} minutes'
                      : '1 hour',
                ),
                onTap: () {
                  provider.startSleepTimer(option);
                  Navigator.pop(sheetContext);
                },
              ),
            if (remaining != null)
              ListTile(
                leading: const Icon(
                  Icons.close_rounded,
                  color: Colors.redAccent,
                ),
                title: const Text(
                  'Cancel timer',
                  style: TextStyle(color: Colors.redAccent),
                ),
                onTap: () {
                  provider.cancelSleepTimer();
                  Navigator.pop(sheetContext);
                },
              ),
          ],
        ),
      ),
    );
  }

  void _showQueueBottomSheet(
    BuildContext context,
    MusicPlayerProvider provider,
  ) {
    showModalBottomSheet(
      context: context,
      backgroundColor: AppTheme.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      // Watches the provider so reorders and removals redraw the sheet in
      // place — a modal route does not rebuild with the screen behind it.
      builder: (_) => Consumer<MusicPlayerProvider>(
        builder: (_, queueProvider, _) => Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text(
                    'Playing Queue',
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                  ),
                  Text(
                    '${queueProvider.queue.length} tracks',
                    style: const TextStyle(fontSize: 12, color: Colors.white54),
                  ),
                ],
              ),
            ),
            Expanded(
              child: queueProvider.queue.isEmpty
                  ? const Center(
                      child: Text(
                        'Queue is empty.',
                        style: TextStyle(color: Colors.white54),
                      ),
                    )
                  : ReorderableListView.builder(
                      itemCount: queueProvider.queue.length,
                      // onReorderItem already reports newIndex as a
                      // position in the final list, which moveInQueue expects.
                      onReorderItem: queueProvider.moveInQueue,
                      itemBuilder: (_, index) {
                        final item = queueProvider.queue[index];
                        final isCurrent = index == queueProvider.currentIndex;
                        return ListTile(
                          key: ValueKey('${item.id}_$index'),
                          leading: Icon(
                            isCurrent ? Icons.volume_up : Icons.music_note,
                            color: isCurrent ? AppTheme.accent : Colors.white38,
                          ),
                          title: Text(
                            item.title,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              color: isCurrent ? AppTheme.accent : Colors.white,
                            ),
                          ),
                          subtitle: Text(
                            item.artist,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                          trailing: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              IconButton(
                                icon: const Icon(Icons.close_rounded, size: 18),
                                color: Colors.white38,
                                tooltip: 'Remove from queue',
                                onPressed: () =>
                                    queueProvider.removeFromQueue(index),
                              ),
                              ReorderableDragStartListener(
                                index: index,
                                child: const Padding(
                                  padding: EdgeInsets.only(right: 4),
                                  child: Icon(
                                    Icons.drag_handle_rounded,
                                    color: Colors.white38,
                                  ),
                                ),
                              ),
                            ],
                          ),
                          onTap: () {
                            queueProvider.playQueueItem(index);
                            Navigator.pop(context);
                          },
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
    );
  }

  static double _artSide(BuildContext context) {
    final size = MediaQuery.sizeOf(context);
    final byWidth = size.width * 0.75;
    final byHeight = size.height * 0.4;
    return byWidth < byHeight ? byWidth : byHeight;
  }

  String _formatDuration(Duration duration) {
    String twoDigits(int n) => n.toString().padLeft(2, '0');
    final minutes = twoDigits(duration.inMinutes.remainder(60));
    final seconds = twoDigits(duration.inSeconds.remainder(60));
    // Podcast episodes routinely run past an hour — without this, 1:05:23
    // displayed as 05:23.
    if (duration.inHours > 0) return '${duration.inHours}:$minutes:$seconds';
    return '$minutes:$seconds';
  }
}
