import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../models/media_item_model.dart';
import '../../providers/music_player_provider.dart';
import '../theme/app_theme.dart';
import '../widgets/add_to_playlist_sheet.dart';
import '../widgets/local_artwork.dart';
import '../widgets/mini_player.dart';
import '../widgets/selectable_track_list.dart';
import '../widgets/track_tile.dart';

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
            icon: Icon(
              Icons.play_arrow_rounded,
              color: context.colors.accent,
              size: 28,
            ),
            tooltip: 'Play all',
            onPressed: songs.isEmpty
                ? null
                : () => context.read<MusicPlayerProvider>().playTrack(
                    songs.first,
                    playlist: songs,
                  ),
          ),
          PopupMenuButton<String>(
            icon: Icon(
              Icons.more_vert_rounded,
              color: context.colors.mist.withValues(alpha: 0.7),
            ),
            tooltip: 'More options',
            onSelected: (action) {
              final messenger = ScaffoldMessenger.of(context);
              if (songs.isEmpty) {
                showCompactSnack(
                  messenger,
                  'Collection is empty',
                  icon: Icons.info_outline_rounded,
                );
                return;
              }
              final provider = context.read<MusicPlayerProvider>();
              if (action == 'play_next') {
                provider.playNextAll(songs);
                showCompactSnack(
                  messenger,
                  songs.length == 1
                      ? 'Playing next: ${songs.first.title}'
                      : 'Playing next: ${songs.length} songs',
                  icon: Icons.playlist_play_rounded,
                );
              } else if (action == 'add_to_queue') {
                provider.addAllToQueue(songs);
                showCompactSnack(
                  messenger,
                  songs.length == 1
                      ? 'Added to queue: ${songs.first.title}'
                      : 'Added ${songs.length} songs to queue',
                  icon: Icons.queue_music_rounded,
                );
              } else if (action == 'add_to_playlist') {
                showAddToPlaylistSheet(context, songs);
              }
            },
            itemBuilder: (_) => const [
              PopupMenuItem(value: 'play_next', child: Text('Play next')),
              PopupMenuItem(
                value: 'add_to_queue',
                child: Text('Add to play queue'),
              ),
              PopupMenuItem(
                value: 'add_to_playlist',
                child: Text('Add to playlist'),
              ),
            ],
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
            child: SelectableTrackList(
              songs: songs,
              bottomPadding: 16,
              searchable: true,
            ),
          ),
        ],
      ),
      bottomNavigationBar: const MiniPlayer(useSafeArea: true),
    );
  }
}
