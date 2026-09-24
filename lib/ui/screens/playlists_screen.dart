import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../models/media_item_model.dart';
import '../../models/playlist.dart';
import '../../models/track_query.dart';
import '../../providers/music_player_provider.dart';
import '../../services/youtube_service.dart';
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
  String? _sizedFor;

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
    final playerProvider = context.watch<MusicPlayerProvider>();
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
              icon: Icon(Icons.add_rounded, color: context.colors.accent),
              tooltip: 'New playlist',
              onPressed: () async {
                final name = await promptForPlaylistName(context);
                if (name == null || name.isEmpty) return;
                if (!context.mounted) return;
                await context.read<MusicPlayerProvider>().createPlaylist(name);
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

  Widget _buildDownloadLocationHeader(
    BuildContext context,
    MusicPlayerProvider provider,
  ) {
    final customPath = provider.customDownloadPath;
    final isCustom = customPath != null && customPath.isNotEmpty;
    final displayPath = isCustom
        ? customPath
        : 'Internal Storage / Android / data / com.pulse.music / files / Music';

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: context.colors.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: context.colors.mist.withValues(alpha: 0.10)),
      ),
      child: Row(
        children: [
          Icon(
            isCustom ? Icons.folder_special_rounded : Icons.folder_rounded,
            color: context.colors.accent,
            size: 22,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Text(
                      isCustom ? 'Custom Location' : 'Default Location',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.bold,
                        color: context.colors.accent,
                      ),
                    ),
                    if (isCustom) ...[
                      const SizedBox(width: 8),
                      GestureDetector(
                        onTap: () => provider.setCustomDownloadPath(null),
                        child: Text(
                          'Reset',
                          style: TextStyle(
                            fontSize: 11,
                            color: context.colors.mist.withValues(alpha: 0.54),
                            decoration: TextDecoration.underline,
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
                const SizedBox(height: 2),
                Text(
                  displayPath,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontSize: 11, color: context.colors.mist.withValues(alpha: 0.60)),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          TextButton(
            onPressed: () async {
              final selectedDir = await FilePicker.getDirectoryPath(
                dialogTitle: 'Select Download Folder',
              );
              if (selectedDir == null || selectedDir.isEmpty) return;
              if (!await YoutubeService.isWritableDirectory(
                Directory(selectedDir),
              )) {
                if (!context.mounted) return;
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text(
                      "Pulse can't save files in that folder. Pick one inside Music or Download.",
                    ),
                  ),
                );
                return;
              }
              await provider.setCustomDownloadPath(selectedDir);
            },
            style: TextButton.styleFrom(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              minimumSize: Size.zero,
              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
            ),
            child: Text(
              'Change',
              style: TextStyle(color: context.colors.accent, fontSize: 12),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDownloadsList(MusicPlayerProvider provider) {
    final downloads = filterTracks(provider.getDownloads(), _query);

    return Column(
      children: [
        _buildDownloadLocationHeader(context, provider),
        if (downloads.isEmpty)
          Expanded(
            child: _buildEmpty(
              Icons.download_done,
              _query.isEmpty
                  ? 'No downloads yet.\nTap the download icon on any online track.'
                  : 'No downloads match your search.',
            ),
          )
        else ...[
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 4),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  '${downloads.length} downloaded',
                  style: TextStyle(color: context.colors.mist.withValues(alpha: 0.60)),
                ),
                FutureBuilder<int>(
                  future: _sizeFuture(provider),
                  builder: (_, snapshot) => Text(
                    snapshot.hasData ? _formatBytes(snapshot.data!) : '',
                    style: TextStyle(color: context.colors.mist.withValues(alpha: 0.38), fontSize: 12),
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
      ],
    );
  }

  /// Recomputes only when the set of downloads changes — keyed on all of them,
  /// not the search-filtered list, so typing doesn't re-stat every file and
  /// swapping one download for another doesn't leave a stale total.
  Future<int> _sizeFuture(MusicPlayerProvider provider) {
    final key = provider.getDownloads().map((d) => d.id).join(',');
    if (_downloadsSize == null || _sizedFor != key) {
      _sizedFor = key;
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
            ? 'No playlists yet.'
            : 'No playlists match your search.',
        action: _query.isEmpty
            ? ElevatedButton.icon(
                onPressed: () async {
                  final provider = context.read<MusicPlayerProvider>();
                  final name = await promptForPlaylistName(context);
                  if (name == null || name.isEmpty) return;
                  await provider.createPlaylist(name);
                },
                icon: const Icon(Icons.add_rounded),
                label: const Text('Create Playlist'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: context.colors.accent,
                  foregroundColor: Colors.black,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
              )
            : null,
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
            style: TextStyle(fontSize: 12, color: context.colors.mist.withValues(alpha: 0.60)),
          ),
          trailing: IconButton(
            icon: Icon(Icons.more_vert, color: context.colors.mist.withValues(alpha: 0.38)),
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
      backgroundColor: context.colors.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (sheetContext) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (playlist.items.isNotEmpty)
              ListTile(
                leading: Icon(Icons.play_arrow_rounded, color: context.colors.accent),
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
              leading: Icon(Icons.edit_rounded, color: context.colors.accent),
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
        backgroundColor: context.colors.surface,
        title: Text('Delete playlist?'),
        content: Text(
          '"${playlist.name}" and its ${playlist.length} tracks will be removed. '
          'This cannot be undone.',
          style: TextStyle(color: context.colors.mist.withValues(alpha: 0.70)),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: Text('Cancel', style: TextStyle(color: context.colors.mist.withValues(alpha: 0.54))),
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

  Widget _buildEmpty(IconData icon, String message, {Widget? action}) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, size: 80, color: context.colors.mist.withValues(alpha: 0.24)),
            const SizedBox(height: 16),
            Text(
              message,
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 16, color: context.colors.mist.withValues(alpha: 0.60)),
            ),
            if (action != null) ...[
              const SizedBox(height: 20),
              action,
            ],
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
