import 'package:audio_service/audio_service.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../providers/music_player_provider.dart';
import '../theme/app_theme.dart';
import '../widgets/lyrics_view.dart';

/// Lyrics filling the screen (karaoke), following the song as it changes.
class FullScreenLyrics extends StatelessWidget {
  const FullScreenLyrics({super.key});

  @override
  Widget build(BuildContext context) {
    return Theme(
      data: AppTheme.darkTheme,
      child: Scaffold(
        backgroundColor: Colors.black,
        appBar: AppBar(
          backgroundColor: Colors.black,
          leading: IconButton(
            tooltip: 'Close',
            icon: const Icon(Icons.fullscreen_exit_rounded),
            onPressed: () => Navigator.pop(context),
          ),
          title: Consumer<MusicPlayerProvider>(
            builder: (_, p, _) => Text(
              p.currentTrack?.title ?? '',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          actions: [
            Consumer<MusicPlayerProvider>(
              builder: (_, p, _) => StreamBuilder<PlaybackState>(
                stream: p.playbackState,
                builder: (_, s) => IconButton(
                  tooltip: 'Play or pause',
                  icon: Icon(
                    (s.data?.playing ?? false)
                        ? Icons.pause_rounded
                        : Icons.play_arrow_rounded,
                  ),
                  onPressed: p.togglePlayPause,
                ),
              ),
            ),
          ],
        ),
        body: Consumer<MusicPlayerProvider>(
          builder: (_, p, _) {
            // A new song while open: fetch its lyrics (no-op if loaded).
            Future.microtask(p.ensureLyricsLoaded);
            final lyrics = p.currentLyrics;
            if (p.isLoadingLyrics) {
              return const Center(child: CircularProgressIndicator());
            }
            if (lyrics == null) {
              return const Center(
                child: Text(
                  'No lyrics found for this song.',
                  style: TextStyle(color: Colors.white60),
                ),
              );
            }
            return Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              child: MediaQuery.withClampedTextScaling(
                // Bigger than the Now Playing panel: read from arm's length.
                minScaleFactor: 1.3,
                child: LyricsView(
                  key: ValueKey(lyrics),
                  lyrics: lyrics,
                  positions: p.positionStream,
                  duration: () => p.currentDuration,
                  onSeek: p.audioHandler.seek,
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}
