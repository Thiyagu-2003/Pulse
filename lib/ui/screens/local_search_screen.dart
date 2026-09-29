import 'dart:io';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../models/local_models.dart';
import '../../models/media_folder.dart';
import '../../models/media_item_model.dart';
import '../../providers/music_player_provider.dart';
import '../theme/app_theme.dart';
import '../widgets/local_artwork.dart';
import '../widgets/mini_player.dart';
import '../widgets/track_tile.dart';
import 'folder_songs_screen.dart';
import 'local_collection_screen.dart';

enum LocalSearchFilter {
  all('All'),
  songs('Songs'),
  albums('Albums'),
  artists('Artists'),
  folders('Folders');

  final String label;
  const LocalSearchFilter(this.label);
}

class LocalSearchScreen extends StatefulWidget {
  final List<AppMediaItem> allSongs;

  const LocalSearchScreen({super.key, required this.allSongs});

  @override
  State<LocalSearchScreen> createState() => _LocalSearchScreenState();
}

class _LocalSearchScreenState extends State<LocalSearchScreen> {
  final TextEditingController _controller = TextEditingController();
  LocalSearchFilter _filter = LocalSearchFilter.all;
  String _query = '';

  late final List<LocalAlbum> _allAlbums;
  late final List<LocalArtist> _allArtists;
  late final List<MediaFolder> _allFolders;

  @override
  void initState() {
    super.initState();
    _allAlbums = groupByAlbum(widget.allSongs);
    _allArtists = groupByArtist(widget.allSongs);
    _allFolders = groupByFolder(widget.allSongs);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _clear() {
    _controller.clear();
    setState(() => _query = '');
  }

  @override
  Widget build(BuildContext context) {
    final q = _query.trim().toLowerCase();

    final matchingSongs = q.isEmpty
        ? <AppMediaItem>[]
        : widget.allSongs.where((s) {
            return s.title.toLowerCase().contains(q) ||
                s.artist.toLowerCase().contains(q) ||
                s.album.toLowerCase().contains(q);
          }).toList();

    final matchingAlbums = q.isEmpty
        ? <LocalAlbum>[]
        : _allAlbums.where((a) {
            return a.name.toLowerCase().contains(q) ||
                a.artist.toLowerCase().contains(q);
          }).toList();

    final matchingArtists = q.isEmpty
        ? <LocalArtist>[]
        : _allArtists.where((ar) => ar.name.toLowerCase().contains(q)).toList();

    final matchingFolders = q.isEmpty
        ? <MediaFolder>[]
        : _allFolders.where((f) => f.name.toLowerCase().contains(q) || f.path.toLowerCase().contains(q)).toList();

    final hasResults = matchingSongs.isNotEmpty ||
        matchingAlbums.isNotEmpty ||
        matchingArtists.isNotEmpty ||
        matchingFolders.isNotEmpty;

    return Scaffold(
      appBar: AppBar(
        titleSpacing: 0,
        title: Padding(
          padding: const EdgeInsets.only(right: 16),
          child: TextField(
            controller: _controller,
            autofocus: true,
            textInputAction: TextInputAction.search,
            style: TextStyle(color: context.colors.mist),
            decoration: InputDecoration(
              hintText: 'Search songs, artists, albums, folders...',
              hintStyle: TextStyle(
                color: context.colors.mist.withValues(alpha: 0.4),
              ),
              filled: true,
              fillColor: context.colors.lift,
              prefixIcon: Icon(
                Icons.search_rounded,
                color: context.colors.mist.withValues(alpha: 0.6),
              ),
              suffixIcon: _controller.text.isEmpty
                  ? null
                  : IconButton(
                      tooltip: 'Clear search',
                      icon: const Icon(Icons.clear_rounded),
                      onPressed: _clear,
                    ),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(28),
                borderSide: BorderSide.none,
              ),
              contentPadding: const EdgeInsets.symmetric(vertical: 12),
            ),
            onChanged: (val) => setState(() => _query = val),
          ),
        ),
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(48),
          child: SizedBox(
            height: 44,
            child: ListView.separated(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              scrollDirection: Axis.horizontal,
              itemCount: LocalSearchFilter.values.length,
              separatorBuilder: (_, _) => const SizedBox(width: 8),
              itemBuilder: (context, index) {
                final f = LocalSearchFilter.values[index];
                final isSelected = _filter == f;
                int count = 0;
                switch (f) {
                  case LocalSearchFilter.all:
                    count = matchingSongs.length + matchingAlbums.length + matchingArtists.length + matchingFolders.length;
                    break;
                  case LocalSearchFilter.songs:
                    count = matchingSongs.length;
                    break;
                  case LocalSearchFilter.albums:
                    count = matchingAlbums.length;
                    break;
                  case LocalSearchFilter.artists:
                    count = matchingArtists.length;
                    break;
                  case LocalSearchFilter.folders:
                    count = matchingFolders.length;
                    break;
                }

                return ChoiceChip(
                  showCheckmark: false,
                  label: Text(q.isEmpty ? f.label : '${f.label} ($count)'),
                  selected: isSelected,
                  selectedColor: context.colors.accent.withValues(alpha: 0.2),
                  backgroundColor: context.colors.lift,
                  labelStyle: TextStyle(
                    color: isSelected ? context.colors.accent : context.colors.mist,
                    fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                    fontSize: 13,
                  ),
                  side: BorderSide(
                    color: isSelected
                        ? context.colors.accent
                        : context.colors.mist.withValues(alpha: 0.1),
                  ),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
                  onSelected: (_) => setState(() => _filter = f),
                );
              },
            ),
          ),
        ),
      ),
      bottomNavigationBar: const MiniPlayer(),
      body: q.isEmpty
          ? _buildInitialView(context)
          : !hasResults
              ? _buildNoResultsView(context)
              : _buildResultsView(
                  context,
                  matchingSongs,
                  matchingAlbums,
                  matchingArtists,
                  matchingFolders,
                ),
    );
  }

  Widget _buildInitialView(BuildContext context) {
    final recent = getNewlyAdded(widget.allSongs, limit: 8);

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        if (recent.isNotEmpty) ...[
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 8),
            child: Text(
              'Recently added',
              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
            ),
          ),
          ...recent.map(
            (song) => TrackTile(
              item: song,
              playlist: recent,
            ),
          ),
          const SizedBox(height: 16),
        ],
        const Padding(
          padding: EdgeInsets.symmetric(vertical: 8),
          child: Text(
            'Quick browse',
            style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
          ),
        ),
        Row(
          children: [
            Expanded(
              child: _buildQuickCard(
                context,
                title: 'Albums',
                subtitle: '${_allAlbums.length} albums',
                icon: Icons.album_rounded,
                color: Colors.blueAccent,
                onTap: () => setState(() => _filter = LocalSearchFilter.albums),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: _buildQuickCard(
                context,
                title: 'Artists',
                subtitle: '${_allArtists.length} artists',
                icon: Icons.person_rounded,
                color: Colors.orangeAccent,
                onTap: () => setState(() => _filter = LocalSearchFilter.artists),
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(
              child: _buildQuickCard(
                context,
                title: 'Folders',
                subtitle: '${_allFolders.length} folders',
                icon: Icons.folder_rounded,
                color: Colors.amber,
                onTap: () => setState(() => _filter = LocalSearchFilter.folders),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: _buildQuickCard(
                context,
                title: 'All songs',
                subtitle: '${widget.allSongs.length} songs',
                icon: Icons.music_note_rounded,
                color: Colors.greenAccent,
                onTap: () => setState(() => _filter = LocalSearchFilter.songs),
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildQuickCard(
    BuildContext context, {
    required String title,
    required String subtitle,
    required IconData icon,
    required Color color,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(16),
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: context.colors.lift,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: context.colors.mist.withValues(alpha: 0.08)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icon, color: color, size: 28),
            const SizedBox(height: 8),
            Text(title, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
            const SizedBox(height: 2),
            Text(
              subtitle,
              style: TextStyle(fontSize: 12, color: context.colors.mist.withValues(alpha: 0.6)),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildNoResultsView(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.search_off_rounded, size: 64, color: context.colors.mist.withValues(alpha: 0.4)),
          const SizedBox(height: 16),
          Text(
            'No results for "$_query"',
            style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
          ),
          const SizedBox(height: 8),
          Text(
            'Check spelling or try a different search',
            style: TextStyle(color: context.colors.mist.withValues(alpha: 0.6), fontSize: 14),
          ),
        ],
      ),
    );
  }

  Widget _buildResultsView(
    BuildContext context,
    List<AppMediaItem> songs,
    List<LocalAlbum> albums,
    List<LocalArtist> artists,
    List<MediaFolder> folders,
  ) {
    final showAll = _filter == LocalSearchFilter.all;

    return ListView(
      padding: const EdgeInsets.symmetric(vertical: 12),
      children: [
        // Action Bar for songs
        if (songs.isNotEmpty && (showAll || _filter == LocalSearchFilter.songs))
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  'Songs (${songs.length})',
                  style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                ),
                Row(
                  children: [
                    IconButton(
                      icon: Icon(Icons.shuffle_rounded, color: context.colors.accent, size: 20),
                      tooltip: 'Shuffle',
                      onPressed: () => context.read<MusicPlayerProvider>().shuffleAll(songs),
                    ),
                    IconButton(
                      icon: Icon(Icons.play_arrow_rounded, color: context.colors.accent, size: 24),
                      tooltip: 'Play all',
                      onPressed: () => context.read<MusicPlayerProvider>().playTrack(songs.first, playlist: songs),
                    ),
                  ],
                ),
              ],
            ),
          ),

        if (songs.isNotEmpty && (showAll || _filter == LocalSearchFilter.songs))
          ...songs.take(showAll ? 6 : songs.length).map(
                (s) => TrackTile(
                  item: s,
                  playlist: songs,
                ),
              ),

        // Albums Section
        if (albums.isNotEmpty && (showAll || _filter == LocalSearchFilter.albums)) ...[
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
            child: Text(
              'Albums (${albums.length})',
              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
            ),
          ),
          ...albums.take(showAll ? 4 : albums.length).map((a) {
            return ListTile(
              leading: ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: a.songs.isNotEmpty
                    ? LocalArtwork(item: a.songs.first, size: 48)
                    : Container(
                        width: 48,
                        height: 48,
                        color: context.colors.lift,
                        child: const Icon(Icons.album_rounded),
                      ),
              ),
              title: Text(a.name, maxLines: 1, overflow: TextOverflow.ellipsis),
              subtitle: Text('${a.artist} · ${a.length} songs'),
              trailing: const Icon(Icons.chevron_right_rounded),
              onTap: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => LocalCollectionScreen(
                      title: a.name,
                      subtitle: '${a.length} songs · ${a.artist}',
                      songs: a.songs,
                    ),
                  ),
                );
              },
            );
          }),
        ],

        // Artists Section
        if (artists.isNotEmpty && (showAll || _filter == LocalSearchFilter.artists)) ...[
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
            child: Text(
              'Artists (${artists.length})',
              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
            ),
          ),
          ...artists.take(showAll ? 4 : artists.length).map((ar) {
            return ListTile(
              leading: CircleAvatar(
                radius: 24,
                backgroundColor: AppTheme.primary.withValues(alpha: 0.2),
                child: const Icon(Icons.person_rounded, color: AppTheme.primary),
              ),
              title: Text(ar.name, maxLines: 1, overflow: TextOverflow.ellipsis),
              subtitle: Text('${ar.length} songs · ${ar.albumCount} albums'),
              trailing: const Icon(Icons.chevron_right_rounded),
              onTap: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => LocalCollectionScreen(
                      title: ar.name,
                      subtitle: '${ar.length} songs',
                      songs: ar.songs,
                    ),
                  ),
                );
              },
            );
          }),
        ],

        // Folders Section
        if (folders.isNotEmpty && (showAll || _filter == LocalSearchFilter.folders)) ...[
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
            child: Text(
              'Folders (${folders.length})',
              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
            ),
          ),
          ...folders.take(showAll ? 4 : folders.length).map((f) {
            final isSdCard = f.path.startsWith('/storage/') && !f.path.startsWith('/storage/emulated');
            return ListTile(
              leading: CircleAvatar(
                radius: 24,
                backgroundColor: Colors.amber.withValues(alpha: 0.15),
                child: Icon(
                  isSdCard ? Icons.sd_card_rounded : Icons.folder_rounded,
                  color: Colors.amber,
                ),
              ),
              title: Text(f.name, maxLines: 1, overflow: TextOverflow.ellipsis),
              subtitle: Text(
                '${f.length} songs · ${File(f.path).path}',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              trailing: const Icon(Icons.chevron_right_rounded),
              onTap: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => FolderSongsScreen(folder: f),
                  ),
                );
              },
            );
          }),
        ],
      ],
    );
  }
}
