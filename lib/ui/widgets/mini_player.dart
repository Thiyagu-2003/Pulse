import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:audio_service/audio_service.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../../providers/music_player_provider.dart';
import '../theme/app_theme.dart';
import '../screens/now_playing_screen.dart';
import 'glass_container.dart';
import 'play_pause_button.dart';

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
              // Dark in both themes: it sits on the blurred artwork, like
              // every music player's full-screen view. Wrapping the route (not
              // just the screen) keeps its sheets dark too.
              pageBuilder: (_, animation, secondaryAnimation) => Theme(
                data: AppTheme.darkTheme,
                child: const NowPlayingScreen(),
              ),
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
                            color: context.colors.mist.withValues(alpha: 0.10),
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
                        style: TextStyle(
                          fontSize: 12,
                          color: context.colors.mist.withValues(alpha: 0.60),
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
                        PlayPauseButton(
                          isPlaying: playing,
                          onPressed: playerProvider.togglePlayPause,
                        ),
                        IconButton(
                          icon: Icon(
                            Icons.skip_next_rounded,
                            color: context.colors.mist.withValues(alpha: 0.7),
                            size: 26,
                          ),
                          tooltip: 'Next',
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
            StreamBuilder<Duration>(
              stream: playerProvider.positionStream,
              builder: (context, snapshot) {
                final position =
                    (snapshot.data ?? Duration.zero).inMilliseconds.toDouble();
                final duration =
                    playerProvider.currentDuration?.inMilliseconds.toDouble() ?? 1.0;

                final progress = (duration > 0) ? (position / duration).clamp(0.0, 1.0) : 0.0;

                return ClipRRect(
                  borderRadius: BorderRadius.circular(2),
                  child: LinearProgressIndicator(
                    value: progress,
                    minHeight: 2,
                    backgroundColor: context.colors.mist.withValues(alpha: 0.10),
                    valueColor: AlwaysStoppedAnimation<Color>(context.colors.accent),
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
