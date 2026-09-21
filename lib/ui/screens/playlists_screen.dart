import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../models/media_item_model.dart';
import '../../models/playlist.dart';
import '../../models/track_query.dart';
import '../../providers/music_player_provider.dart';
import '../theme/app_theme.dart';
import '../widgets/add_to_playlist_sheet.dart';
import '../widgets/track_filter_bar.dart';
import '../widgets/track_tile.dart';
import 'playlist_detail_screen.dart';

class PlaylistsScreen extends StatefulWidget {
  const PlaylistsScreen({super.key});

  @override
  State<PlaylistsScreen> createState() => _PlaylistsScreenState();
}

class _PlaylistsScreenState extends State<PlaylistsScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;
  int _tabIndex = 0;
  String _query = '';
  TrackSort _sort = TrackSort.title;

  /// Held rather than rebuilt inside the FutureBuilder: a future created in
  /// build restarts on every rebuild, and this one stats every downloaded
  /// file on disk.
  Future<int>? _downloadsSize;
  int _sizedForCount = -1;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 4, vsync: this);
    _tabController.addListener(() {
      // Rebuild on any tab change, not just taps: the app bar's "+" button
      // and the filter bar's sort control depend on the active tab, and
      // swiping between tabs never called setState.
      if (_tabController.indexIsChanging || _tabIndex != _tabController.index) {
        setState(() {
          _tabIndex = _tabController.index;
          // A query typed against favourites means nothing on the next tab.
          _query = '';
        });
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final playerProvider = Provider.of<MusicPlayerProvider>(context);
    final tabIndex = _tabIndex;

    return Scaffold(
      appBar: AppBar(
        title: Text(
          'Library & Playlists',
          style: Theme.of(context).textTheme.displaySmall,
        ),
        actions: [
          if (tabIndex == 2)
            IconButton(
              icon: const Icon(Icons.add_rounded, color: AppTheme.accent),
              tooltip: 'New playlist',
              onPressed: () async {
                final name = await promptForPlaylistName(context);
                if (name == null || name.isEmpty) return;
                await playerProvider.createPlaylist(name);
              },
            ),
        ],
        // Colours come from the theme's tabBarTheme so every tab strip in the
        // app agrees.
        bottom: TabBar(
          controller: _tabController,
          onTap: (_) => setState(() {}),
          isScrollable: true,
          tabAlignment: TabAlignment.start,
          indicatorSize: TabBarIndicatorSize.label,
          tabs: const [
            Tab(icon: Icon(Icons.favorite_rounded, size: 20), text: 'Favorites'),
            Tab(icon: Icon(Icons.history_rounded, size: 20), text: 'History'),
            Tab(icon: Icon(Icons.queue_music_rounded, size: 20), text: 'Playlists'),
            Tab(icon: Icon(Icons.download_done_rounded, size: 20), text: 'Downloads'),
          ],
        ),
      ),
      body: Column(
        children: [
          TrackFilterBar(
            query: _query,
            onQueryChanged: (value) => setState(() => _query = value),
            hintText: tabIndex == 2
                ? 'Search playlists...'
                : 'Search title, artist, album...',
            // History is chronological — sorting it would destroy the only
            // thing it means. Playlists sort by name, not by track.
            sort: tabIndex == 0 ? _sort : null,
            onSortChanged:
                tabIndex == 0 ? (value) => setState(() => _sort = value) : null,
          ),
          Expanded(
            child: TabBarView(
              controller: _tabController,
              children: [
                _buildTrackList(
                  sortTracks(
                    filterTracks(playerProvider.getFavorites(), _query),
                    _sort,
                  ),
                  emptyMessage: 'No favorite songs added yet.',
                  emptyIcon: Icons.favorite_border,
                ),
                _buildTrackList(
                  filterTracks(playerProvider.getHistory(), _query),
                  emptyMessage: 'Listening history is empty.',
                  emptyIcon: Icons.history,
                ),
                _buildPlaylistList(playerProvider),
                _buildDownloadsList(playerProvider),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDownloadsList(MusicPlayerProvider provider) {
    final downloads = filterTracks(provider.getDownloads(), _query);

    if (downloads.isEmpty) {
      return _buildEmpty(
        Icons.download_done,
        _query.isEmpty
            ? 'No downloads yet.\nTap the download icon on any online track.'
            : 'No downloads match your search.',
      );
    }

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                '${downloads.length} downloaded',
                style: const TextStyle(color: Colors.white60),
              ),
              // Sized on demand: the numbers come from the filesystem, and a
              // file removed outside the app simply stops counting.
              FutureBuilder<int>(
                future: _sizeFuture(provider, downloads.length),
                builder: (_, snapshot) => Text(
                  snapshot.hasData ? _formatBytes(snapshot.data!) : '',
                  style: const TextStyle(color: Colors.white38, fontSize: 12),
                ),
              ),
            ],
          ),
        ),
        Expanded(
          child: ListView.builder(
            itemCount: downloads.length,
            itemBuilder: (context, index) {
              final item = downloads[index];
              return Dismissible(
                key: ValueKey('download_${item.id}'),
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
                onDismissed: (_) => provider.deleteDownload(item),
                child: TrackTile(item: item, playlist: downloads),
              );
            },
          ),
        ),
      ],
    );
  }

  /// Recomputes only when the number of downloads changes, so scrolling or an
  /// unrelated provider notification doesn't re-stat every file on disk.
  Future<int> _sizeFuture(MusicPlayerProvider provider, int count) {
    if (_downloadsSize == null || _sizedForCount != count) {
      _sizedForCount = count;
      _downloadsSize = provider.downloadedBytes();
    }
    return _downloadsSize!;
  }

  String _formatBytes(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(0)} KB';
    if (bytes < 1024 * 1024 * 1024) {
      return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
    }
    return '${(bytes / (1024 * 1024 * 1024)).toStringAsFixed(2)} GB';
  }

  Widget _buildPlaylistList(MusicPlayerProvider provider) {
    final needle = _query.trim().toLowerCase();
    final playlists = provider
        .getPlaylists()
        .where((p) => p.name.toLowerCase().contains(needle))
        .toList();

    if (playlists.isEmpty) {
      return _buildEmpty(
        Icons.queue_music,
        _query.isEmpty
            ? 'No playlists yet.\nTap + to create one.'
            : 'No playlists match your search.',
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.symmetric(vertical: 8),
      itemCount: playlists.length,
      itemBuilder: (context, index) {
        final playlist = playlists[index];
        return ListTile(
          leading: Container(
            width: 48,
            height: 48,
            decoration: BoxDecoration(
              color: AppTheme.primary.withValues(alpha: 0.2),
              borderRadius: BorderRadius.circular(10),
            ),
            child: const Icon(Icons.queue_music, color: AppTheme.primary),
          ),
          title: Text(
            playlist.name,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontWeight: FontWeight.w600),
          ),
          subtitle: Text(
            '${playlist.length} tracks',
            style: const TextStyle(fontSize: 12, color: Colors.white60),
          ),
          trailing: IconButton(
            icon: const Icon(Icons.more_vert, color: Colors.white38),
            onPressed: () => _showPlaylistActions(playlist, provider),
          ),
          onTap: () => Navigator.push(
            context,
            MaterialPageRoute(
              builder: (_) => PlaylistDetailScreen(playlistId: playlist.id),
            ),
          ),
        );
      },
    );
  }

  void _showPlaylistActions(Playlist playlist, MusicPlayerProvider provider) {
    showModalBottomSheet(
      context: context,
      backgroundColor: AppTheme.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (sheetContext) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (playlist.items.isNotEmpty)
              ListTile(
                leading: const Icon(Icons.play_arrow_rounded, color: AppTheme.accent),
                title: Text('Play all'),
                onTap: () {
                  provider.playTrack(
                    playlist.items.first,
                    playlist: playlist.items,
                  );
                  Navigator.pop(sheetContext);
                },
              ),
            ListTile(
              leading: const Icon(Icons.edit_rounded, color: AppTheme.accent),
              title: Text('Rename'),
              onTap: () async {
                Navigator.pop(sheetContext);
                final name = await promptForPlaylistName(
                  context,
                  initial: playlist.name,
                  title: 'Rename playlist',
                );
                if (name == null || name.isEmpty) return;
                await provider.renamePlaylist(playlist.id, name);
              },
            ),
            ListTile(
              leading: const Icon(Icons.delete_outline_rounded, color: Colors.redAccent),
              title: Text('Delete', style: TextStyle(color: Colors.redAccent)),
              onTap: () async {
                Navigator.pop(sheetContext);
                final confirmed = await _confirmDelete(playlist);
                if (confirmed) await provider.deletePlaylist(playlist.id);
              },
            ),
          ],
        ),
      ),
    );
  }

  /// Deleting a playlist throws away work and can't be undone, so it asks.
  Future<bool> _confirmDelete(Playlist playlist) async {
    final result = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        backgroundColor: AppTheme.surface,
        title: Text('Delete playlist?'),
        content: Text(
          '"${playlist.name}" and its ${playlist.length} tracks will be removed. '
          'This cannot be undone.',
          style: const TextStyle(color: Colors.white70),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Cancel', style: TextStyle(color: Colors.white54)),
          ),
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('Delete', style: TextStyle(color: Colors.redAccent)),
          ),
        ],
      ),
    );
    return result ?? false;
  }

  Widget _buildTrackList(
    List<AppMediaItem> tracks, {
    required String emptyMessage,
    required IconData emptyIcon,
  }) {
    if (tracks.isEmpty) {
      return _buildEmpty(
        emptyIcon,
        _query.isEmpty ? emptyMessage : 'Nothing matches your search.',
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.symmetric(vertical: 12),
      itemCount: tracks.length,
      itemBuilder: (context, index) {
        return TrackTile(item: tracks[index], playlist: tracks);
      },
    );
  }

  Widget _buildEmpty(IconData icon, String message) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, size: 80, color: Colors.white24),
            const SizedBox(height: 16),
            Text(
              message,
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 16, color: Colors.white60),
            ),
          ],
        ),
      ),
    );
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }
}
