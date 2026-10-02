import 'dart:io';
import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:provider/provider.dart';
import 'package:audio_service/audio_service.dart';
import '../../models/media_item_model.dart';
import '../../models/playback_mode.dart';
import '../../providers/music_player_provider.dart';
import '../theme/app_theme.dart';
import '../widgets/add_to_playlist_sheet.dart';
import '../widgets/glass_container.dart';
import '../widgets/lyrics_view.dart';
import '../widgets/track_tile.dart';
import '../../services/platform_bridge.dart';
import '../../services/saavn_service.dart';
import '../../models/media_folder.dart';
import '../../services/local_music_service.dart';
import '../widgets/local_artwork.dart';
import 'artist_screen.dart';
import 'equalizer_screen.dart';
import 'folder_songs_screen.dart';
import 'full_screen_lyrics.dart';
import 'local_collection_screen.dart';
import 'ringtone_editor_screen.dart';
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
    final playbackSpeed = playerProvider.speed;
    final isPodcast =
        playerProvider.currentTrack?.sourceType == MediaSourceType.podcast;
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
            )
          else if (track.sourceType == MediaSourceType.local)
            Positioned.fill(
              child: LocalArtwork(
                item: track,
                fit: BoxFit.cover,
                size: 800,
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
                      IconButton(
                        tooltip: 'More options',
                        icon: const Icon(
                          Icons.more_horiz_rounded,
                          color: Colors.white70,
                        ),
                        onPressed: () =>
                            _showOptions(context, playerProvider, track),
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
                            : Stack(
                                children: [
                                  LyricsView(
                                    // A new song starts a fresh view.
                                    key: ValueKey(playerProvider.currentLyrics),
                                    lyrics: playerProvider.currentLyrics!,
                                    positions: playerProvider.positionStream,
                                    duration: () =>
                                        playerProvider.currentDuration,
                                    onSeek: playerProvider.audioHandler.seek,
                                  ),
                                  Positioned(
                                    top: 0,
                                    right: 0,
                                    child: IconButton(
                                      tooltip: 'Full screen lyrics',
                                      icon: const Icon(
                                        Icons.fullscreen_rounded,
                                        color: Colors.white70,
                                      ),
                                      onPressed: () => Navigator.push(
                                        context,
                                        MaterialPageRoute(
                                          builder: (_) =>
                                              const FullScreenLyrics(),
                                        ),
                                      ),
                                    ),
                                  ),
                                ],
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
                                : track.sourceType == MediaSourceType.local
                                ? LocalArtwork(
                                    item: track,
                                    fit: BoxFit.cover,
                                    size: 500,
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
                      // The video player is a phone web view; not on desktop.
                      if (track.sourceType == MediaSourceType.youtube &&
                          (Platform.isAndroid || Platform.isIOS))
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
                              const speeds = [0.75, 1.0, 1.25, 1.5, 1.75, 2.0];
                              final next =
                                  speeds[(speeds.indexOf(playbackSpeed) + 1) %
                                      speeds.length];
                              await playerProvider.setSpeed(next);
                            },
                          ),

                          // Podcasts: jump within the episode instead.
                          isPodcast
                              ? IconButton(
                                  iconSize: 36,
                                  tooltip: 'Back 10 seconds',
                                  icon: const Icon(Icons.replay_10_rounded),
                                  onPressed: () => playerProvider.seekBy(
                                    const Duration(seconds: -10),
                                  ),
                                )
                              : IconButton(
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

                          isPodcast
                              ? IconButton(
                                  iconSize: 36,
                                  tooltip: 'Forward 30 seconds',
                                  icon: const Icon(Icons.forward_30_rounded),
                                  onPressed: () => playerProvider.seekBy(
                                    const Duration(seconds: 30),
                                  ),
                                )
                              : IconButton(
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

  /// ⋯ — everything about the song playing: quick actions (download, radio,
  /// share) on top, then add to playlist, album, artist, equalizer, sleep
  /// timer.
  void _showOptions(
    BuildContext context,
    MusicPlayerProvider provider,
    AppMediaItem track,
  ) {
    final rootContext = Navigator.of(context).context;
    final messenger = ScaffoldMessenger.of(context);
    final artistId = track.extras?[SaavnService.artistIdKey] as String?;
    final albumId = track.extras?[SaavnService.albumIdKey] as String?;
    final link = shareLinkFor(track);
    final downloaded = provider.isDownloaded(track.id);
    final canDownload = track.sourceType.isOnline && !downloaded;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppTheme.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (sheetContext) {
        void close() => Navigator.pop(sheetContext);
        Widget round(IconData icon, String label, VoidCallback? onTap) =>
            Column(
              children: [
                IconButton.filledTonal(
                  iconSize: 26,
                  padding: const EdgeInsets.all(14),
                  tooltip: label,
                  icon: Icon(icon),
                  onPressed: onTap,
                ),
                const SizedBox(height: 4),
                Text(label, style: const TextStyle(fontSize: 12)),
              ],
            );
        Widget row(IconData icon, String label, VoidCallback onTap) => ListTile(
          leading: Icon(icon, color: Colors.white),
          title: Text(label),
          trailing: const Icon(Icons.chevron_right_rounded),
          onTap: () {
            close();
            onTap();
          },
        );
        return SafeArea(
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(24, 20, 24, 12),
                  child: Text(
                    '${track.title} · ${track.artist}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(color: Colors.white70),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                    children: [
                      if (downloaded)
                        round(Icons.download_done_rounded, 'Remove', () {
                          close();
                          removeDownload(rootContext, track);
                        })
                      else
                        round(
                          Icons.download_rounded,
                          'Download',
                          canDownload
                              ? () {
                                  close();
                                  startDownload(rootContext, track);
                                }
                              : null,
                        ),
                      round(Icons.sensors_rounded, 'Start radio', () async {
                        close();
                        final n = await provider.startRadio();
                        showCompactSnack(
                          messenger,
                          n == 0
                              ? "Couldn't find songs like this one"
                              : 'Radio: $n songs like this queued',
                          icon: Icons.sensors_rounded,
                          error: n == 0,
                        );
                      }),
                      round(
                        Icons.share_rounded,
                        'Share',
                        () async {
                          close();
                          final shareText = link != null
                              ? '${track.title} – ${track.artist}\n$link'
                              : '${track.title} – ${track.artist}';
                          final shared = await PlatformBridge.share(shareText);
                          if (!shared) {
                            showCompactSnack(
                              messenger,
                              'Track info copied',
                              icon: Icons.copy_rounded,
                            );
                          }
                        },
                      ),
                    ],
                  ),
                ),
                const Divider(color: Colors.white12),
                row(
                  Icons.playlist_add_rounded,
                  'Add to playlist',
                  () => showAddToPlaylistSheet(rootContext, [track]),
                ),
                if (albumId != null)
                  row(
                    Icons.album_rounded,
                    'View album',
                    () => openCollection(
                      rootContext,
                      SaavnCollection(
                        kind: SaavnKind.album,
                        id: albumId,
                        title: track.album,
                        subtitle: '',
                        image: '',
                      ),
                    ),
                  )
                else if (track.sourceType == MediaSourceType.local &&
                    track.album.trim().isNotEmpty &&
                    track.album != 'Local Storage')
                  row(
                    Icons.album_rounded,
                    'View album',
                    () {
                      final all = LocalMusicService.instance.cachedSongs;
                      final albumTracks = all
                          .where((s) => s.album.trim() == track.album.trim())
                          .toList();
                      Navigator.push(
                        rootContext,
                        MaterialPageRoute(
                          builder: (_) => LocalCollectionScreen(
                            title: track.album,
                            subtitle: '${albumTracks.length} tracks',
                            songs: albumTracks.isNotEmpty ? albumTracks : [track],
                          ),
                        ),
                      );
                    },
                  ),
                if (artistId != null)
                  row(
                    Icons.person_rounded,
                    'Go to artist',
                    () => openCollection(
                      rootContext,
                      SaavnCollection(
                        kind: SaavnKind.artist,
                        id: artistId,
                        title: track.artist.split(',').first.trim(),
                        subtitle: '',
                        image: '',
                      ),
                    ),
                  )
                else if (track.sourceType == MediaSourceType.local &&
                    track.artist.trim().isNotEmpty &&
                    track.artist != 'Unknown Artist')
                  row(
                    Icons.person_rounded,
                    'Go to artist',
                    () {
                      final all = LocalMusicService.instance.cachedSongs;
                      final artistTracks = all
                          .where((s) => s.artist.trim() == track.artist.trim())
                          .toList();
                      Navigator.push(
                        rootContext,
                        MaterialPageRoute(
                          builder: (_) => LocalCollectionScreen(
                            title: track.artist,
                            subtitle: '${artistTracks.length} tracks',
                            songs: artistTracks.isNotEmpty ? artistTracks : [track],
                          ),
                        ),
                      );
                    },
                  ),
                if (track.sourceType == MediaSourceType.local) ...[
                  row(
                    Icons.folder_rounded,
                    'Show in folder',
                    () {
                      final filePath = (track.extras?['filePath'] as String?) ??
                          track.streamUrl ??
                          (track.id.startsWith('/') ? track.id : '');
                      final folderPath = File(filePath).parent.path;
                      final all = LocalMusicService.instance.cachedSongs;
                      final folderSongs = all.where((s) {
                        final p = (s.extras?['filePath'] as String?) ??
                            s.streamUrl ??
                            (s.id.startsWith('/') ? s.id : '');
                        return File(p).parent.path == folderPath;
                      }).toList();
                      Navigator.push(
                        rootContext,
                        MaterialPageRoute(
                          builder: (_) => FolderSongsScreen(
                            folder: MediaFolder(
                              path: folderPath,
                              items: folderSongs.isNotEmpty ? folderSongs : [track],
                            ),
                          ),
                        ),
                      );
                    },
                  ),
                  row(
                    Icons.info_outline_rounded,
                    'Track details',
                    () => _showTrackDetails(rootContext, track),
                  ),
                ],
                if (Platform.isAndroid) ...[
                  row(
                    Icons.equalizer_rounded,
                    'Equaliser',
                    () => Navigator.push(
                      rootContext,
                      MaterialPageRoute(
                        builder: (_) => const EqualizerScreen(),
                      ),
                    ),
                  ),
                  row(
                    Icons.ring_volume_rounded,
                    'Set as ringtone',
                    () => Navigator.push(
                      rootContext,
                      MaterialPageRoute(
                        builder: (_) => RingtoneEditorScreen(item: track),
                      ),
                    ),
                  ),
                ],
                row(
                  Icons.bedtime_rounded,
                  'Sleep timer',
                  () => _showSleepTimerSheet(context, provider),
                ),
                TextButton(onPressed: close, child: const Text('Dismiss')),
              ],
            ),
          ),
        );
      },
    );
  }

  void _showTrackDetails(BuildContext context, AppMediaItem track) {
    final filePath = (track.extras?['filePath'] as String?) ??
        track.streamUrl ??
        (track.id.startsWith('/') ? track.id : '');
    final file = File(filePath);
    String fileSizeStr = 'Unknown';
    if (file.existsSync()) {
      final bytes = file.lengthSync();
      fileSizeStr = '${(bytes / (1024 * 1024)).toStringAsFixed(2)} MB';
    }
    final isSdCard = filePath.startsWith('/storage/') && !filePath.startsWith('/storage/emulated');
    final durationStr = track.duration != null
        ? '${track.duration!.inMinutes}:${(track.duration!.inSeconds % 60).toString().padLeft(2, '0')}'
        : 'Unknown';

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Row(
          children: [
            Icon(Icons.info_outline_rounded, color: AppTheme.accent),
            SizedBox(width: 8),
            Text('Track details', style: TextStyle(fontSize: 18)),
          ],
        ),
        content: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              _detailRow('Title', track.title),
              _detailRow('Artist', track.artist),
              _detailRow('Album', track.album),
              _detailRow('Duration', durationStr),
              _detailRow('File size', fileSizeStr),
              _detailRow('Storage location', isSdCard ? 'SD Card (Removable)' : 'Internal Storage'),
              _detailRow('File path', filePath),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Close'),
          ),
        ],
      ),
    );
  }

  static Widget _detailRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Colors.white54),
          ),
          const SizedBox(height: 2),
          SelectableText(
            value,
            style: const TextStyle(fontSize: 13, color: Colors.white),
          ),
        ],
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
    final isEndOfQueue = provider.sleepTimerEndOfQueue;

    showModalBottomSheet(
      context: context,
      backgroundColor: AppTheme.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (sheetContext) => SafeArea(
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
                child: Text(
                  isEndOfQueue
                      ? 'Stopping at end of playlist'
                      : remaining != null
                          ? 'Pausing in ${remaining.inMinutes + 1} min'
                          : 'Sleep timer',
                  style: const TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    color: AppTheme.mist,
                  ),
                ),
              ),
              // End of playlist / queue option
              ListTile(
                leading: Icon(
                  Icons.queue_music_rounded,
                  color: isEndOfQueue ? AppTheme.accent : Colors.white70,
                ),
                title: Text(
                  'End of playlist / queue',
                  style: TextStyle(
                    fontWeight:
                        isEndOfQueue ? FontWeight.bold : FontWeight.normal,
                    color: isEndOfQueue ? AppTheme.accent : Colors.white,
                  ),
                ),
                subtitle: Text(
                  provider.queue.isEmpty
                      ? 'Queue is empty'
                      : '${(provider.queue.length - provider.currentIndex).clamp(0, provider.queue.length)} track(s) remaining',
                  style: TextStyle(
                    color: isEndOfQueue
                        ? AppTheme.accent.withValues(alpha: 0.8)
                        : Colors.white38,
                    fontSize: 12,
                  ),
                ),
                trailing: isEndOfQueue
                    ? const Icon(
                        Icons.check_circle_rounded,
                        color: AppTheme.accent,
                      )
                    : null,
                onTap: provider.queue.isEmpty
                    ? null
                    : () {
                        final messenger = ScaffoldMessenger.of(context);
                        provider.startSleepTimerEndOfQueue();
                        Navigator.pop(sheetContext);
                        showCompactSnack(
                          messenger,
                          'Sleep timer: stopping at end of playlist',
                          icon: Icons.queue_music_rounded,
                        );
                      },
              ),
              Divider(
                height: 1,
                thickness: 1,
                color: AppTheme.mist.withValues(alpha: 0.08),
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
                    style: const TextStyle(color: Colors.white),
                  ),
                  onTap: () {
                    final messenger = ScaffoldMessenger.of(context);
                    provider.startSleepTimer(option);
                    Navigator.pop(sheetContext);
                    showCompactSnack(
                      messenger,
                      'Sleep timer set for ${option.inMinutes < 60 ? "${option.inMinutes} minutes" : "1 hour"}',
                      icon: Icons.bedtime_outlined,
                    );
                  },
                ),
              // Custom duration option
              ListTile(
                leading: const Icon(
                  Icons.more_time_rounded,
                  color: Colors.white70,
                ),
                title: const Text(
                  'Custom duration...',
                  style: TextStyle(color: Colors.white),
                ),
                subtitle: const Text(
                  'Set a custom time in minutes',
                  style: TextStyle(color: Colors.white38, fontSize: 12),
                ),
                onTap: () {
                  Navigator.pop(sheetContext);
                  _showCustomSleepTimerDialog(context, provider);
                },
              ),
              if (provider.hasSleepTimer)
                ListTile(
                  leading: const Icon(
                    Icons.close_rounded,
                    color: Colors.redAccent,
                  ),
                  title: const Text(
                    'Cancel timer',
                    style: TextStyle(
                      color: Colors.redAccent,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  onTap: () {
                    final messenger = ScaffoldMessenger.of(context);
                    provider.cancelSleepTimer();
                    Navigator.pop(sheetContext);
                    showCompactSnack(
                      messenger,
                      'Sleep timer turned off',
                      icon: Icons.timer_off_rounded,
                    );
                  },
                ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _showCustomSleepTimerDialog(
    BuildContext context,
    MusicPlayerProvider provider,
  ) async {
    final controller = TextEditingController(text: '20');
    final messenger = ScaffoldMessenger.of(context);

    await showDialog<void>(
      context: context,
      builder: (dialogContext) {
        return StatefulBuilder(
          builder: (dialogCtx, setDialogState) {
            final parsed = int.tryParse(controller.text) ?? 0;
            return AlertDialog(
              backgroundColor: AppTheme.surface,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(20),
              ),
              title: const Row(
                children: [
                  Icon(Icons.more_time_rounded,
                      color: AppTheme.accent, size: 24),
                  SizedBox(width: 8),
                  Text(
                    'Custom sleep timer',
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                      color: AppTheme.mist,
                    ),
                  ),
                ],
              ),
              content: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Enter duration in minutes:',
                      style: TextStyle(
                        color: AppTheme.mist.withValues(alpha: 0.70),
                        fontSize: 14,
                      ),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: controller,
                      keyboardType: TextInputType.number,
                      autofocus: true,
                      style: const TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                        color: AppTheme.mist,
                      ),
                      decoration: InputDecoration(
                        suffixText: 'min',
                        suffixStyle: TextStyle(
                          color: AppTheme.mist.withValues(alpha: 0.60),
                          fontSize: 16,
                        ),
                        filled: true,
                        fillColor: AppTheme.lift,
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                          borderSide: BorderSide.none,
                        ),
                        focusedBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                          borderSide: const BorderSide(
                            color: AppTheme.primary,
                            width: 2,
                          ),
                        ),
                      ),
                      onChanged: (_) => setDialogState(() {}),
                    ),
                    const SizedBox(height: 16),
                    Text(
                      'Quick presets:',
                      style: TextStyle(
                        color: AppTheme.mist.withValues(alpha: 0.50),
                        fontSize: 12,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [10, 20, 30, 60, 90, 120].map((mins) {
                        final isSelected = parsed == mins;
                        return ChoiceChip(
                          label: Text('${mins}m'),
                          selected: isSelected,
                          selectedColor: AppTheme.primary,
                          backgroundColor: AppTheme.lift,
                          labelStyle: TextStyle(
                            color: isSelected ? Colors.white : AppTheme.mist,
                            fontWeight: isSelected
                                ? FontWeight.bold
                                : FontWeight.normal,
                          ),
                          onSelected: (_) {
                            controller.text = mins.toString();
                            controller.selection = TextSelection.fromPosition(
                              TextPosition(offset: controller.text.length),
                            );
                            setDialogState(() {});
                          },
                        );
                      }).toList(),
                    ),
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(dialogContext),
                  child: Text(
                    'Cancel',
                    style: TextStyle(
                      color: AppTheme.mist.withValues(alpha: 0.60),
                    ),
                  ),
                ),
                FilledButton(
                  style: FilledButton.styleFrom(
                    backgroundColor: AppTheme.primary,
                    foregroundColor: Colors.white,
                  ),
                  onPressed: parsed <= 0
                      ? null
                      : () {
                          provider.startSleepTimer(Duration(minutes: parsed));
                          Navigator.pop(dialogContext);
                          final hours = parsed ~/ 60;
                          final mins = parsed % 60;
                          final formatted = hours > 0
                              ? (mins > 0
                                  ? '${hours}h ${mins}m'
                                  : '${hours}h')
                              : '$mins min';
                          showCompactSnack(
                            messenger,
                            'Sleep timer set for $formatted',
                            icon: Icons.bedtime_outlined,
                          );
                        },
                  child: const Text('Start timer'),
                ),
              ],
            );
          },
        );
      },
    );
  }

  void _showQueueBottomSheet(
    BuildContext context,
    MusicPlayerProvider provider,
  ) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      showDragHandle: false,
      backgroundColor: Colors.transparent,
      builder: (sheetContext) => const _QueueBottomSheet(),
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

class _QueueBottomSheet extends StatefulWidget {
  const _QueueBottomSheet();

  @override
  State<_QueueBottomSheet> createState() => _QueueBottomSheetState();
}

class _QueueBottomSheetState extends State<_QueueBottomSheet> {
  final DraggableScrollableController _sheetController =
      DraggableScrollableController();

  static const double _initialSize = 0.55;
  static const double _minSize = 0.35;
  static const double _maxSize = 0.95;

  @override
  void dispose() {
    _sheetController.dispose();
    super.dispose();
  }

  void _handleVerticalDragUpdate(
    DragUpdateDetails details,
    BuildContext context,
  ) {
    if (!_sheetController.isAttached) return;
    final screenHeight = MediaQuery.sizeOf(context).height;
    if (screenHeight <= 0) return;
    final delta = -details.primaryDelta! / screenHeight;
    final next = (_sheetController.size + delta).clamp(_minSize, _maxSize);
    _sheetController.jumpTo(next);
  }

  void _handleVerticalDragEnd(
    DragEndDetails details,
    BuildContext context,
  ) {
    if (!_sheetController.isAttached) return;
    final velocity = details.primaryVelocity ?? 0.0;
    // Fast downward fling dismisses the sheet
    if (velocity > 1200) {
      Navigator.of(context).pop();
      return;
    }
    final current = _sheetController.size;
    if (current <= _minSize + 0.02 && velocity >= 0) {
      Navigator.of(context).pop();
      return;
    }
    final double target;
    if (velocity < -400) {
      target = _maxSize;
    } else if (velocity > 400) {
      target = _initialSize;
    } else {
      target = (current - _initialSize).abs() < (current - _maxSize).abs()
          ? _initialSize
          : _maxSize;
    }
    _sheetController.animateTo(
      target,
      duration: const Duration(milliseconds: 250),
      curve: Curves.easeOutCubic,
    );
  }

  void _toggleExpanded() {
    if (!_sheetController.isAttached) return;
    final target = _sheetController.size > 0.75 ? _initialSize : _maxSize;
    _sheetController.animateTo(
      target,
      duration: const Duration(milliseconds: 280),
      curve: Curves.easeInOutCubic,
    );
  }

  Future<void> _confirmClearQueue(
    BuildContext context,
    MusicPlayerProvider queueProvider,
  ) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        backgroundColor: AppTheme.surface,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(20),
        ),
        title: const Row(
          children: [
            Icon(Icons.delete_outline_rounded, color: Colors.redAccent, size: 24),
            SizedBox(width: 8),
            Text(
              'Clear queue?',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
                color: AppTheme.mist,
              ),
            ),
          ],
        ),
        content: Text(
          'This will remove all upcoming songs from the queue.',
          style: TextStyle(
            color: AppTheme.mist.withValues(alpha: 0.70),
            fontSize: 14,
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: Text(
              'Cancel',
              style: TextStyle(
                color: AppTheme.mist.withValues(alpha: 0.60),
              ),
            ),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: Colors.redAccent,
              foregroundColor: Colors.white,
            ),
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('Clear'),
          ),
        ],
      ),
    );

    if (confirmed == true && context.mounted) {
      queueProvider.clearUpNext();
      final messenger = ScaffoldMessenger.of(context);
      showCompactSnack(
        messenger,
        'Cleared upcoming songs',
        icon: Icons.delete_outline_rounded,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return DraggableScrollableSheet(
      controller: _sheetController,
      initialChildSize: _initialSize,
      minChildSize: _minSize,
      maxChildSize: _maxSize,
      snap: true,
      snapSizes: const [_initialSize, _maxSize],
      expand: false,
      builder: (sheetContext, scrollController) {
        return Container(
          decoration: const BoxDecoration(
            color: AppTheme.surface,
            borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
          ),
          child: SafeArea(
            top: false,
            child: Consumer<MusicPlayerProvider>(
              builder: (_, queueProvider, _) {
                return Column(
                  children: [
                    // Draggable header area (handle + title bar)
                    GestureDetector(
                      behavior: HitTestBehavior.opaque,
                      onVerticalDragUpdate: (details) =>
                          _handleVerticalDragUpdate(details, sheetContext),
                      onVerticalDragEnd: (details) =>
                          _handleVerticalDragEnd(details, sheetContext),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Center(
                            child: GestureDetector(
                              onTap: _toggleExpanded,
                              child: Container(
                                margin: const EdgeInsets.only(top: 12, bottom: 8),
                                width: 38,
                                height: 4.5,
                                decoration: BoxDecoration(
                                  color: AppTheme.mist.withValues(alpha: 0.25),
                                  borderRadius: BorderRadius.circular(3),
                                ),
                              ),
                            ),
                          ),
                          Padding(
                            padding: const EdgeInsets.fromLTRB(16, 4, 8, 8),
                            child: Row(
                              children: [
                                Expanded(
                                  child: GestureDetector(
                                    onTap: _toggleExpanded,
                                    child: Text(
                                      'Playing Queue · ${queueProvider.queue.length}',
                                      style: const TextStyle(
                                        fontSize: 18,
                                        fontWeight: FontWeight.bold,
                                        color: AppTheme.mist,
                                      ),
                                    ),
                                  ),
                                ),
                                IconButton(
                                  tooltip: 'Save as playlist',
                                  icon: const Icon(Icons.playlist_add_rounded),
                                  color: AppTheme.mist.withValues(alpha: 0.85),
                                  onPressed: queueProvider.queue.isEmpty
                                      ? null
                                      : () async {
                                          final messenger =
                                              ScaffoldMessenger.of(context);
                                          final name =
                                              await promptForPlaylistName(
                                            context,
                                            title: 'Save queue as playlist',
                                          );
                                          if (name == null || name.isEmpty) {
                                            return;
                                          }
                                          await queueProvider
                                              .saveQueueAsPlaylist(name);
                                          showCompactSnack(
                                            messenger,
                                            'Saved playlist: $name',
                                            icon: Icons
                                                .playlist_add_check_rounded,
                                          );
                                        },
                                ),
                                IconButton(
                                  tooltip: 'Clear queue',
                                  icon: const Icon(Icons.delete_outline_rounded),
                                  color: Colors.redAccent,
                                  disabledColor: Colors.white24,
                                  onPressed: queueProvider.queue.length < 2
                                      ? null
                                      : () => _confirmClearQueue(
                                            context,
                                            queueProvider,
                                          ),
                                ),
                              ],
                            ),
                          ),
                          Divider(
                            height: 1,
                            thickness: 1,
                            color: AppTheme.mist.withValues(alpha: 0.08),
                          ),
                        ],
                      ),
                    ),
                    Expanded(
                      child: queueProvider.queue.isEmpty
                          ? ListView(
                              controller: scrollController,
                              children: [
                                Padding(
                                  padding: const EdgeInsets.only(top: 60),
                                  child: Center(
                                    child: Text(
                                      'Queue is empty.',
                                      style: TextStyle(
                                        color: AppTheme.mist
                                            .withValues(alpha: 0.54),
                                      ),
                                    ),
                                  ),
                                ),
                              ],
                            )
                          : ReorderableListView.builder(
                              scrollController: scrollController,
                              buildDefaultDragHandles: false,
                              padding: const EdgeInsets.only(bottom: 24),
                              itemCount: queueProvider.queue.length,
                              onReorder: (from, to) {
                                if (from < to) to -= 1;
                                queueProvider.moveInQueue(from, to);
                              },
                              itemBuilder: (itemContext, index) {
                                final item = queueProvider.queue[index];
                                final isCurrent =
                                    index == queueProvider.currentIndex;
                                return Dismissible(
                                  key: ValueKey(item.id),
                                  onDismissed: (_) =>
                                      queueProvider.removeFromQueue(index),
                                  background: Container(
                                    color: Colors.red.withValues(alpha: 0.3),
                                  ),
                                  child: ListTile(
                                    leading: Icon(
                                      isCurrent
                                          ? Icons.volume_up
                                          : Icons.music_note,
                                      color: isCurrent
                                          ? AppTheme.accent
                                          : Colors.white38,
                                    ),
                                    title: Text(
                                      item.title,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: TextStyle(
                                        color: isCurrent
                                            ? AppTheme.accent
                                            : Colors.white,
                                      ),
                                    ),
                                    subtitle: Text(
                                      item.artist,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: const TextStyle(
                                        color: Colors.white60,
                                      ),
                                    ),
                                    trailing: Row(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        IconButton(
                                          icon: const Icon(
                                            Icons.close_rounded,
                                            size: 18,
                                          ),
                                          color: Colors.white38,
                                          tooltip: 'Remove from queue',
                                          onPressed: () => queueProvider
                                              .removeFromQueue(index),
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
                                  ),
                                );
                              },
                            ),
                    ),
                  ],
                );
              },
            ),
          ),
        );
      },
    );
  }
}
