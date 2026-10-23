import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../models/media_folder.dart';
import '../../providers/music_player_provider.dart';
import '../theme/app_theme.dart';
import '../widgets/add_to_playlist_sheet.dart';
import '../widgets/mini_player.dart';
import '../widgets/selectable_track_list.dart';
import '../widgets/track_tile.dart';

/// The tracks inside one device folder — Music, Recordings, Call recordings.
class FolderSongsScreen extends StatelessWidget {
  final MediaFolder folder;

  const FolderSongsScreen({super.key, required this.folder});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              folder.name,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 20),
            ),
            Text(
              '${folder.length} ${folder.length == 1 ? 'track' : 'tracks'}',
              style: TextStyle(
                fontSize: 12,
                color: context.colors.mist.withValues(alpha: 0.54),
              ),
            ),
          ],
        ),
        actions: [
          IconButton(
            icon: Icon(Icons.shuffle_rounded, color: context.colors.accent),
            tooltip: 'Shuffle',
            onPressed: folder.items.isEmpty
                ? null
                : () => context.read<MusicPlayerProvider>().shuffleAll(
                    folder.items,
                  ),
          ),
          IconButton(
            icon: Icon(Icons.play_arrow_rounded, color: context.colors.accent),
            tooltip: 'Play all',
            onPressed: folder.items.isEmpty
                ? null
                : () => context.read<MusicPlayerProvider>().playTrack(
                    folder.items.first,
                    playlist: folder.items,
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
              if (folder.items.isEmpty) {
                showCompactSnack(
                  messenger,
                  'Folder is empty',
                  icon: Icons.info_outline_rounded,
                );
                return;
              }
              final provider = context.read<MusicPlayerProvider>();
              if (action == 'play_next') {
                provider.playNextAll(folder.items);
                showCompactSnack(
                  messenger,
                  folder.items.length == 1
                      ? 'Playing next: ${folder.items.first.title}'
                      : 'Playing next: ${folder.items.length} songs',
                  icon: Icons.playlist_play_rounded,
                );
              } else if (action == 'add_to_queue') {
                provider.addAllToQueue(folder.items);
                showCompactSnack(
                  messenger,
                  folder.items.length == 1
                      ? 'Added to queue: ${folder.items.first.title}'
                      : 'Added ${folder.items.length} songs to queue',
                  icon: Icons.queue_music_rounded,
                );
              } else if (action == 'add_to_playlist') {
                showAddToPlaylistSheet(context, folder.items);
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
      // Pushed over the tabs, so it needs its own mini player.
      bottomNavigationBar: const MiniPlayer(useSafeArea: true),
      // Queue only this folder, so a call recording can't run on into the
      // next one just because it happened to be next on disk.
      body: SelectableTrackList(
        songs: folder.items,
        bottomPadding: 16,
        searchable: true,
      ),
    );
  }
}
