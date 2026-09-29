import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../models/media_item_model.dart';
import '../../providers/music_player_provider.dart';
import '../theme/app_theme.dart';
import '../widgets/local_artwork.dart';
import '../widgets/selectable_track_list.dart';

/// Screen displaying tracks for a specific local Album, Artist, Folder, or Genre.
class LocalCollectionScreen extends StatelessWidget {
  final String title;
  final String? subtitle;
  final List<AppMediaItem> songs;
  final int? artworkId;
  final IconData? fallbackIcon;

  const LocalCollectionScreen({
    super.key,
    required this.title,
    this.subtitle,
    required this.songs,
    this.artworkId,
    this.fallbackIcon,
  });

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 18),
            ),
            if (subtitle != null)
              Text(
                subtitle!,
                style: TextStyle(
                  fontSize: 12,
                  color: context.colors.mist.withValues(alpha: 0.60),
                ),
              ),
          ],
        ),
        actions: [
          IconButton(
            icon: Icon(Icons.shuffle_rounded, color: context.colors.accent),
            tooltip: 'Shuffle',
            onPressed: songs.isEmpty
                ? null
                : () => context.read<MusicPlayerProvider>().shuffleAll(songs),
          ),
          IconButton(
            icon: Icon(Icons.play_arrow_rounded, color: context.colors.accent, size: 28),
            tooltip: 'Play all',
            onPressed: songs.isEmpty
                ? null
                : () => context.read<MusicPlayerProvider>().playTrack(
                      songs.first,
                      playlist: songs,
                    ),
          ),
        ],
      ),
      body: Column(
        children: [
          // Header Card
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            child: Row(
              children: [
                CollageArtwork(
                  items: songs,
                  size: 72,
                  defaultIcon: fallbackIcon ?? Icons.library_music_rounded,
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        '${songs.length} ${songs.length == 1 ? 'song' : 'songs'}',
                        style: TextStyle(
                          fontSize: 13,
                          color: context.colors.mist.withValues(alpha: 0.65),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const Divider(height: 1),
          Expanded(
            child: SelectableTrackList(songs: songs),
          ),
        ],
      ),
    );
  }
}
