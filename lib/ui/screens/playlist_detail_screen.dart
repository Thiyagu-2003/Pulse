import 'package:audio_service/audio_service.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../models/track_query.dart';
import '../../providers/music_player_provider.dart';
import '../theme/app_theme.dart';
import '../widgets/add_to_playlist_sheet.dart';
import '../widgets/mini_player.dart';
import '../widgets/track_filter_bar.dart';
import '../widgets/playing_indicator.dart';
import '../widgets/track_tile.dart';

class PlaylistDetailScreen extends StatefulWidget {
  final String playlistId;

  const PlaylistDetailScreen({super.key, required this.playlistId});

  @override
  State<PlaylistDetailScreen> createState() => _PlaylistDetailScreenState();
}

class _PlaylistDetailScreenState extends State<PlaylistDetailScreen> {
  String _query = '';

  String get playlistId => widget.playlistId;

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
            style: TextStyle(
              color: context.colors.mist.withValues(alpha: 0.54),
            ),
          ),
        ),
      );
    }

    final shown = filterTracks(playlist.items, _query);

    return Scaffold(
      appBar: AppBar(
        title: Text(
          playlist.name,
          style: const TextStyle(fontWeight: FontWeight.bold),
        ),
        actions: [
          if (playlist.items.isNotEmpty)
            IconButton(
              icon: Icon(
                Icons.shuffle_rounded,
                color: context.colors.mist.withValues(alpha: 0.70),
              ),
              tooltip: 'Shuffle',
              onPressed: () => provider.shuffleAll(playlist.items),
            ),
          DownloadAllButton(
            items: playlist.items,
            playlistName: playlist.name,
            playlistId: playlist.id,
          ),
          IconButton(
            icon: Icon(
              Icons.edit_rounded,
              color: context.colors.mist.withValues(alpha: 0.70),
            ),
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
                padding: const EdgeInsets.all(32),
                child: Text(
                  'Nothing here yet.\nLong-press any track to add it.',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: context.colors.mist.withValues(alpha: 0.54),
                  ),
                ),
              ),
            )
          : Column(
              children: [
                Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 20,
                    vertical: 8,
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Row(
                        children: [
                          Text(
                            '${playlist.length} tracks',
                            style: TextStyle(
                              color: context.colors.mist.withValues(alpha: 0.60),
                            ),
                          ),
                          if (provider.isCollectionPlaying(playlist.items)) ...[
                            const SizedBox(width: 8),
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 6,
                                vertical: 1.5,
                              ),
                              decoration: BoxDecoration(
                                color: AppTheme.primary.withValues(alpha: 0.16),
                                borderRadius: BorderRadius.circular(6),
                                border: Border.all(
                                  color: AppTheme.primary.withValues(alpha: 0.35),
                                ),
                              ),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  StreamBuilder<PlaybackState>(
                                    stream: provider.playbackState,
                                    builder: (_, snap) => PlayingIndicator(
                                      isPlaying: snap.data?.playing ?? false,
                                      size: 10,
                                      color: AppTheme.primary,
                                    ),
                                  ),
                                  const SizedBox(width: 4),
                                  const Text(
                                    'Playing',
                                    style: TextStyle(
                                      fontSize: 10,
                                      fontWeight: FontWeight.bold,
                                      color: AppTheme.primary,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ],
                      ),
                      Wrap(
                        spacing: 8,
                        children: [
                          OutlinedButton.icon(
                            style: OutlinedButton.styleFrom(
                              foregroundColor: context.colors.mist,
                              side: BorderSide(
                                color: context.colors.mist.withValues(
                                  alpha: 0.25,
                                ),
                              ),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(12),
                              ),
                              padding: const EdgeInsets.symmetric(
                                horizontal: 12,
                              ),
                            ),
                            icon: const Icon(
                              Icons.playlist_play_rounded,
                              size: 20,
                            ),
                            label: const Text('Play Next'),
                            onPressed: () {
                              provider.playNextAll(playlist.items);
                              showCompactSnack(
                                ScaffoldMessenger.of(context),
                                'Playing playlist next (${playlist.items.length} songs)',
                                icon: Icons.playlist_play_rounded,
                              );
                            },
                          ),
                          ElevatedButton.icon(
                            style: ElevatedButton.styleFrom(
                              backgroundColor: AppTheme.primary,
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(12),
                              ),
                              padding: const EdgeInsets.symmetric(
                                horizontal: 14,
                              ),
                            ),
                            icon: const Icon(
                              Icons.play_arrow,
                              color: Colors.white,
                            ),
                            label: const Text(
                              'Play All',
                              style: TextStyle(color: Colors.white),
                            ),
                            onPressed: () => provider.playTrack(
                              playlist.items.first,
                              playlist: playlist.items,
                              sourceTitle: 'Playlist: ${playlist.name}',
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                // A match still plays with the whole playlist queued.
                TrackFilterBar(
                  query: _query,
                  onQueryChanged: (q) => setState(() => _query = q),
                ),
                if (shown.isEmpty)
                  Padding(
                    padding: const EdgeInsets.all(24),
                    child: Text(
                      'Nothing matches your search.',
                      style: TextStyle(
                        color: context.colors.mist.withValues(alpha: 0.54),
                      ),
                    ),
                  ),
                Expanded(
                  child: ListView.builder(
                    padding: const EdgeInsets.only(bottom: 16),
                    itemCount: shown.length,
                    itemBuilder: (_, index) {
                      final item = shown[index];
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
                        onDismissed: (_) =>
                            provider.removeFromPlaylist(playlist.id, item.id),
                        child: TrackTile(item: item, playlist: playlist.items),
                      );
                    },
                  ),
                ),
              ],
            ),
      bottomNavigationBar: const MiniPlayer(useSafeArea: true),
    );
  }
}
