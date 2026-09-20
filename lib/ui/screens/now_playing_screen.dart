import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:provider/provider.dart';
import 'package:audio_service/audio_service.dart';
import '../../providers/music_player_provider.dart';
import '../theme/app_theme.dart';
import '../widgets/glass_container.dart';

class NowPlayingScreen extends StatefulWidget {
  const NowPlayingScreen({super.key});

  @override
  State<NowPlayingScreen> createState() => _NowPlayingScreenState();
}

class _NowPlayingScreenState extends State<NowPlayingScreen> {
  bool _showLyrics = false;
  double _playbackSpeed = 1.0;

  @override
  Widget build(BuildContext context) {
    final playerProvider = Provider.of<MusicPlayerProvider>(context);
    final track = playerProvider.currentTrack;

    if (track == null) {
      return Scaffold(
        appBar: AppBar(),
        body: const Center(child: Text('No song selected')),
      );
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
              child: Container(
                color: Colors.black.withValues(alpha: 0.7),
              ),
            ),
          ),

          // Main Player content
          SafeArea(
            child: Column(
              children: [
                // Top Bar
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      IconButton(
                        icon: const Icon(Icons.keyboard_arrow_down, size: 30),
                        onPressed: () => Navigator.pop(context),
                      ),
                      Column(
                        children: [
                          Text(
                            track.sourceType.name.toUpperCase(),
                            style: const TextStyle(
                              fontSize: 10,
                              letterSpacing: 2,
                              color: AppTheme.accent,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          Text(
                            track.album,
                            style: const TextStyle(fontSize: 14, color: Colors.white70),
                          ),
                        ],
                      ),
                      IconButton(
                        icon: Icon(
                          _showLyrics ? Icons.music_note : Icons.lyrics,
                          color: _showLyrics ? AppTheme.accent : Colors.white70,
                        ),
                        onPressed: () {
                          setState(() {
                            _showLyrics = !_showLyrics;
                          });
                        },
                      ),
                    ],
                  ),
                ),

                const Spacer(),

                // Center Content: Artwork OR Synced Lyrics
                if (_showLyrics)
                  Expanded(
                    flex: 8,
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 24),
                      child: GlassContainer(
                        child: playerProvider.isLoadingLyrics
                            ? const Center(child: CircularProgressIndicator())
                            : SingleChildScrollView(
                                child: Text(
                                  playerProvider.currentLyrics ?? 'No lyrics available',
                                  textAlign: TextAlign.center,
                                  style: const TextStyle(
                                    fontSize: 18,
                                    height: 1.8,
                                    fontWeight: FontWeight.w500,
                                    color: Colors.white,
                                  ),
                                ),
                              ),
                      ),
                    ),
                  )
                else
                  Hero(
                    tag: 'artwork_${track.id}',
                    child: Container(
                      width: MediaQuery.of(context).size.width * 0.75,
                      height: MediaQuery.of(context).size.width * 0.75,
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(24),
                        boxShadow: [
                          BoxShadow(
                            color: AppTheme.primary.withValues(alpha: 0.3),
                            blurRadius: 30,
                            spreadRadius: 5,
                          )
                        ],
                      ),
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(24),
                        child: track.artUri != null && track.artUri!.startsWith('http')
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
                StreamBuilder<PlaybackState>(
                  stream: playerProvider.playbackState,
                  builder: (context, snapshot) {
                    final state = snapshot.data;
                    final position = state?.position ?? Duration.zero;
                    final duration = playerProvider.audioHandler.player.duration ??
                        track.duration ??
                        Duration.zero;

                    // Protect against zero/negative duration
                    final maxMs = duration.inMilliseconds.toDouble();
                    final safeDuration = maxMs > 0 ? maxMs : 1.0;
                    final safePosition = position.inMilliseconds.toDouble().clamp(0.0, safeDuration);

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
                              onChanged: (val) {
                                playerProvider.audioHandler
                                    .seek(Duration(milliseconds: val.toInt()));
                              },
                            ),
                          ),
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Text(
                                _formatDuration(position),
                                style: const TextStyle(fontSize: 12, color: Colors.white54),
                              ),
                              Text(
                                _formatDuration(duration),
                                style: const TextStyle(fontSize: 12, color: Colors.white54),
                              ),
                            ],
                          ),
                        ],
                      ),
                    );
                  },
                ),

                const SizedBox(height: 16),

                // Playback Control Buttons
                StreamBuilder<PlaybackState>(
                  stream: playerProvider.playbackState,
                  builder: (context, snapshot) {
                    final state = snapshot.data;
                    final playing = state?.playing ?? false;
                    final processingState = state?.processingState ?? AudioProcessingState.idle;
                    final isBuffering = processingState == AudioProcessingState.buffering ||
                        processingState == AudioProcessingState.loading;

                    return Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                        children: [
                          IconButton(
                            icon: Text(
                              '${_playbackSpeed}x',
                              style: const TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.bold,
                                color: AppTheme.accent,
                              ),
                            ),
                            onPressed: () {
                              setState(() {
                                if (_playbackSpeed == 1.0) {
                                  _playbackSpeed = 1.25;
                                } else if (_playbackSpeed == 1.25) {
                                  _playbackSpeed = 1.5;
                                } else if (_playbackSpeed == 1.5) {
                                  _playbackSpeed = 2.0;
                                } else {
                                  _playbackSpeed = 1.0;
                                }
                              });
                              playerProvider.audioHandler.setSpeed(_playbackSpeed);
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
                            child: Container(
                              width: 70,
                              height: 70,
                              decoration: const BoxDecoration(
                                shape: BoxShape.circle,
                                gradient: LinearGradient(
                                  colors: [AppTheme.primary, AppTheme.accent],
                                ),
                                boxShadow: [
                                  BoxShadow(
                                    color: AppTheme.primary,
                                    blurRadius: 20,
                                    spreadRadius: 2,
                                  )
                                ],
                              ),
                              child: isBuffering
                                  ? const Padding(
                                      padding: EdgeInsets.all(20.0),
                                      child: CircularProgressIndicator(
                                        strokeWidth: 3,
                                        color: Colors.black,
                                      ),
                                    )
                                  : Icon(
                                      playing ? Icons.pause_rounded : Icons.play_arrow_rounded,
                                      size: 40,
                                      color: Colors.black,
                                    ),
                            ),
                          ),

                          IconButton(
                            iconSize: 36,
                            icon: const Icon(Icons.skip_next_rounded),
                            onPressed: playerProvider.skipToNext,
                          ),

                          IconButton(
                            icon: const Icon(Icons.queue_music_rounded, color: Colors.white70),
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

  void _showQueueBottomSheet(BuildContext context, MusicPlayerProvider provider) {
    showModalBottomSheet(
      context: context,
      backgroundColor: AppTheme.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (_) => Column(
        children: [
          const Padding(
            padding: EdgeInsets.all(16),
            child: Text(
              'Playing Queue',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
          ),
          Expanded(
            child: ListView.builder(
              itemCount: provider.queue.length,
              itemBuilder: (_, index) {
                final item = provider.queue[index];
                final isCurrent = index == provider.currentIndex;
                return ListTile(
                  leading: Icon(
                    isCurrent ? Icons.volume_up : Icons.music_note,
                    color: isCurrent ? AppTheme.accent : Colors.white38,
                  ),
                  title: Text(
                    item.title,
                    maxLines: 1,
                    style: TextStyle(
                      color: isCurrent ? AppTheme.accent : Colors.white,
                    ),
                  ),
                  subtitle: Text(item.artist, maxLines: 1),
                  onTap: () {
                    provider.playTrack(item);
                    Navigator.pop(context);
                  },
                );
              },
            ),
          )
        ],
      ),
    );
  }

  String _formatDuration(Duration duration) {
    String twoDigits(int n) => n.toString().padLeft(2, '0');
    final minutes = twoDigits(duration.inMinutes.remainder(60));
    final seconds = twoDigits(duration.inSeconds.remainder(60));
    return '$minutes:$seconds';
  }
}
