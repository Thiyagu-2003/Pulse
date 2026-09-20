import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:audio_service/audio_service.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../../providers/music_player_provider.dart';
import '../theme/app_theme.dart';
import '../screens/now_playing_screen.dart';
import 'glass_container.dart';

class MiniPlayer extends StatelessWidget {
  const MiniPlayer({super.key});

  @override
  Widget build(BuildContext context) {
    final playerProvider = Provider.of<MusicPlayerProvider>(context);
    final track = playerProvider.currentTrack;

    if (track == null) return const SizedBox.shrink();

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      child: GlassContainer(
        borderRadius: 20,
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        onTap: () {
          Navigator.push(
            context,
            PageRouteBuilder(
              pageBuilder: (_, animation, secondaryAnimation) => const NowPlayingScreen(),
              transitionsBuilder: (context, animation, secondaryAnimation, child) {
                return SlideTransition(
                  position: Tween<Offset>(
                    begin: const Offset(0, 1),
                    end: Offset.zero,
                  ).animate(animation),
                  child: child,
                );
              },
            ),
          );
        },
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              children: [
                // Mini Artwork
                Hero(
                  tag: 'artwork_${track.id}',
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(12),
                    child: track.artUri != null && track.artUri!.startsWith('http')
                        ? CachedNetworkImage(
                            imageUrl: track.artUri!,
                            width: 44,
                            height: 44,
                            fit: BoxFit.cover,
                          )
                        : Container(
                            width: 44,
                            height: 44,
                            color: Colors.white10,
                            child: const Icon(Icons.music_note, color: AppTheme.primary),
                          ),
                  ),
                ),
                const SizedBox(width: 12),

                // Title & Artist
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        track.title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 14,
                        ),
                      ),
                      Text(
                        track.artist,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 12,
                          color: Colors.white60,
                        ),
                      ),
                    ],
                  ),
                ),

                // Controls: Play/Pause & Skip
                StreamBuilder<PlaybackState>(
                  stream: playerProvider.playbackState,
                  builder: (context, snapshot) {
                    final playing = snapshot.data?.playing ?? false;
                    return Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        IconButton(
                          icon: Icon(
                            playing ? Icons.pause_rounded : Icons.play_arrow_rounded,
                            color: AppTheme.accent,
                            size: 28,
                          ),
                          onPressed: playerProvider.togglePlayPause,
                        ),
                        IconButton(
                          icon: const Icon(
                            Icons.skip_next_rounded,
                            color: Colors.white70,
                            size: 26,
                          ),
                          onPressed: playerProvider.skipToNext,
                        ),
                      ],
                    );
                  },
                ),
              ],
            ),

            const SizedBox(height: 4),

            // Mini Linear Progress Indicator
            StreamBuilder<PlaybackState>(
              stream: playerProvider.playbackState,
              builder: (context, snapshot) {
                final state = snapshot.data;
                final position = state?.position.inMilliseconds.toDouble() ?? 0.0;
                final duration = playerProvider.audioHandler.player.duration?.inMilliseconds.toDouble() ??
                    track.duration?.inMilliseconds.toDouble() ??
                    1.0;

                final progress = (duration > 0) ? (position / duration).clamp(0.0, 1.0) : 0.0;

                return ClipRRect(
                  borderRadius: BorderRadius.circular(2),
                  child: LinearProgressIndicator(
                    value: progress,
                    minHeight: 2,
                    backgroundColor: Colors.white10,
                    valueColor: const AlwaysStoppedAnimation<Color>(AppTheme.accent),
                  ),
                );
              },
            ),
          ],
        ),
      ),
    );
  }
}
