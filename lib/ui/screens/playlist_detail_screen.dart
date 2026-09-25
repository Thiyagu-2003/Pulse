import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../providers/music_player_provider.dart';
import '../theme/app_theme.dart';
import '../widgets/add_to_playlist_sheet.dart';
import '../widgets/track_tile.dart';

class PlaylistDetailScreen extends StatelessWidget {
  final String playlistId;

  const PlaylistDetailScreen({super.key, required this.playlistId});

  @override
  Widget build(BuildContext context) {
    // Read through the provider on every rebuild rather than holding the
    // playlist, so removals and renames show up immediately.
    final provider = context.watch<MusicPlayerProvider>();
    final playlist = provider.getPlaylist(playlistId);

    if (playlist == null) {
      return Scaffold(
        appBar: AppBar(),
        body: Center(
          child: Text(
            'This playlist no longer exists.',
            style: TextStyle(color: context.colors.mist.withValues(alpha: 0.54)),
          ),
        ),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: Text(
          playlist.name,
          style: const TextStyle(fontWeight: FontWeight.bold),
        ),
        actions: [
          DownloadAllButton(items: playlist.items),
          IconButton(
            icon: Icon(Icons.edit_rounded, color: context.colors.mist.withValues(alpha: 0.70)),
            tooltip: 'Rename',
            onPressed: () async {
              final name = await promptForPlaylistName(
                context,
                initial: playlist.name,
                title: 'Rename playlist',
              );
              if (name == null || name.isEmpty) return;
              await provider.renamePlaylist(playlist.id, name);
            },
          ),
        ],
      ),
      body: playlist.items.isEmpty
          ? Center(
              child: Padding(
                padding: EdgeInsets.all(32),
                child: Text(
                  'Nothing here yet.\nLong-press any track to add it.',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: context.colors.mist.withValues(alpha: 0.54)),
                ),
              ),
            )
          : Column(
              children: [
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        '${playlist.length} tracks',
                        style: TextStyle(color: context.colors.mist.withValues(alpha: 0.60)),
                      ),
                      ElevatedButton.icon(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: AppTheme.primary,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                        icon: const Icon(Icons.play_arrow, color: Colors.white),
                        label: const Text(
                          'Play All',
                          style: TextStyle(color: Colors.white),
                        ),
                        onPressed: () => provider.playTrack(
                          playlist.items.first,
                          playlist: playlist.items,
                        ),
                      ),
                    ],
                  ),
                ),
                Expanded(
                  child: ListView.builder(
                    itemCount: playlist.items.length,
                    itemBuilder: (_, index) {
                      final item = playlist.items[index];
                      return Dismissible(
                        key: ValueKey('${playlist.id}_${item.id}'),
                        direction: DismissDirection.endToStart,
                        background: Container(
                          alignment: Alignment.centerRight,
                          padding: const EdgeInsets.only(right: 32),
                          margin: const EdgeInsets.symmetric(
                            vertical: 4,
                            horizontal: 16,
                          ),
                          decoration: BoxDecoration(
                            color: Colors.redAccent.withValues(alpha: 0.2),
                            borderRadius: BorderRadius.circular(14),
                          ),
                          child: const Icon(
                            Icons.delete_outline_rounded,
                            color: Colors.redAccent,
                          ),
                        ),
                        onDismissed: (_) => provider.removeFromPlaylist(
                          playlist.id,
                          item.id,
                        ),
                        child: TrackTile(
                          item: item,
                          playlist: playlist.items,
                        ),
                      );
                    },
                  ),
                ),
              ],
            ),
    );
  }
}
