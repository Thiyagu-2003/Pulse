import 'package:flutter/material.dart';
import 'package:flutter_spinkit/flutter_spinkit.dart';
import 'package:provider/provider.dart';
import '../../services/local_music_service.dart';
import '../../models/media_folder.dart';
import '../../models/media_item_model.dart';
import '../../models/track_query.dart';
import '../../providers/music_player_provider.dart';
import '../theme/app_theme.dart';
import '../widgets/add_to_playlist_sheet.dart';
import '../widgets/selectable_track_list.dart';
import '../widgets/track_filter_bar.dart';
import 'folder_songs_screen.dart';

class LocalSongsScreen extends StatefulWidget {
  const LocalSongsScreen({super.key});

  @override
  State<LocalSongsScreen> createState() => _LocalSongsScreenState();
}

class _LocalSongsScreenState extends State<LocalSongsScreen>
    with WidgetsBindingObserver {
  final LocalMusicService _localService = LocalMusicService();
  List<AppMediaItem> _localSongs = [];
  bool _isLoading = true;
  bool _hasPermission = false;
  String _query = '';
  TrackSort _sort = TrackSort.title;

  /// Default on: Android's media store returns voice memos and call
  /// recordings mixed in with music, and folders are what separate them.
  bool _groupByFolder = true;

  /// _localSongs stays the untouched source of truth; this is what's shown.
  ///
  /// Cached against the inputs: a library of a few thousand tracks was being
  /// filtered and re-sorted several times per frame, once for every place in
  /// build that asked for the list.
  List<AppMediaItem>? _visibleCache;
  String? _cachedQuery;
  TrackSort? _cachedSort;
  List<AppMediaItem>? _cachedSource;

  List<AppMediaItem> get _visibleSongs {
    if (_visibleCache == null ||
        _cachedQuery != _query ||
        _cachedSort != _sort ||
        !identical(_cachedSource, _localSongs)) {
      _cachedQuery = _query;
      _cachedSort = _sort;
      _cachedSource = _localSongs;
      _visibleCache = sortTracks(filterTracks(_localSongs, _query), _sort);
    }
    return _visibleCache!;
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  /// Back from the system Settings page ("Grant Access" sends the user there
  /// once the permission is permanently denied): check again, or the denied
  /// view stays up although access was just granted.
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // Only *check* here: asking again would pop the system dialog every
    // time the user switches back to the app after saying no.
    if (state == AppLifecycleState.resumed && !_hasPermission && !_isLoading) {
      _localService.hasPermission().then((granted) {
        if (granted && mounted) _initLocalMusic();
      });
    }
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _initLocalMusic();
  }

  Future<void> _initLocalMusic({bool fromButton = false}) async {
    final granted = await _localService.requestPermission(
      openSettingsIfBlocked: fromButton,
    );
    if (granted) {
      final songs = await _localService.fetchLocalSongs();
      if (mounted) {
        setState(() {
          _localSongs = songs;
          _hasPermission = true;
          _isLoading = false;
        });
      }
    } else {
      if (mounted) {
        setState(() {
          _hasPermission = false;
          _isLoading = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(
          'Local Songs',
          style: Theme.of(context).textTheme.displaySmall,
        ),
        actions: [
          IconButton(
            icon: Icon(
              _groupByFolder
                  ? Icons.folder_rounded
                  : Icons.format_list_bulleted_rounded,
              color: context.colors.accent,
            ),
            tooltip: _groupByFolder ? 'Show all songs' : 'Group by folder',
            onPressed: () => setState(() => _groupByFolder = !_groupByFolder),
          ),
          IconButton(
            icon: Icon(Icons.refresh, color: context.colors.accent),
            onPressed: () {
              setState(() => _isLoading = true);
              _initLocalMusic();
            },
          ),
        ],
      ),
      body: _isLoading
          ? Center(
              child: SpinKitDoubleBounce(
                color: context.colors.accent,
                size: 50.0,
              ),
            )
          : !_hasPermission
          ? _buildPermissionDeniedView()
          : _localSongs.isEmpty
          ? _buildEmptyView()
          : Column(
              children: [
                TrackFilterBar(
                  query: _query,
                  onQueryChanged: (value) => setState(() => _query = value),
                  sort: _sort,
                  onSortChanged: (value) => setState(() => _sort = value),
                ),
                Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 20,
                    vertical: 8,
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        _query.isEmpty
                            ? '${_localSongs.length} Songs found'
                            : '${_visibleSongs.length} of ${_localSongs.length}',
                        style: TextStyle(
                          color: context.colors.mist.withValues(alpha: 0.60),
                        ),
                      ),
                      const Spacer(),
                      IconButton(
                        tooltip: 'Shuffle',
                        icon: Icon(
                          Icons.shuffle_rounded,
                          color: context.colors.accent,
                        ),
                        onPressed: () => context
                            .read<MusicPlayerProvider>()
                            .shuffleAll(_visibleSongs),
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
                        onPressed: () {
                          // Queue what's on screen, not the whole
                          // library — otherwise a search result plays
                          // and then wanders off into unfiltered songs.
                          final visible = _visibleSongs;
                          if (visible.isNotEmpty) {
                            final playerProvider =
                                Provider.of<MusicPlayerProvider>(
                                  context,
                                  listen: false,
                                );
                            playerProvider.playTrack(
                              visible.first,
                              playlist: visible,
                            );
                          }
                        },
                      ),
                    ],
                  ),
                ),
                Expanded(
                  child: RefreshIndicator(
                    // Pull down to pick up newly added files.
                    onRefresh: _initLocalMusic,
                    color: context.colors.accent,
                    child: Builder(
                      builder: (context) {
                        final visible = _visibleSongs;
                        if (visible.isEmpty) {
                          return Center(
                            child: Text(
                              'No songs match your search.',
                              style: TextStyle(
                                color: context.colors.mist.withValues(
                                  alpha: 0.54,
                                ),
                              ),
                            ),
                          );
                        }
                        // A search is looking for a track, not a
                        // folder, so results stay flat.
                        if (_groupByFolder && _query.isEmpty) {
                          return _buildFolderList(visible);
                        }
                        return SelectableTrackList(songs: visible);
                      },
                    ),
                  ),
                ),
              ],
            ),
    );
  }

  Widget _buildFolderList(List<AppMediaItem> songs) {
    final folders = groupByFolder(songs);

    return ListView.builder(
      padding: const EdgeInsets.symmetric(vertical: 8),
      itemCount: folders.length,
      itemBuilder: (context, index) {
        final folder = folders[index];
        return ListTile(
          leading: Container(
            width: 46,
            height: 46,
            decoration: BoxDecoration(
              color:
                  (folder.isRecordings ? Colors.orangeAccent : AppTheme.primary)
                      .withValues(alpha: 0.18),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(
              folder.isRecordings ? Icons.mic_rounded : Icons.folder_rounded,
              color: folder.isRecordings
                  ? Colors.orangeAccent
                  : AppTheme.primary,
            ),
          ),
          title: Text(
            folder.name,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontWeight: FontWeight.w600),
          ),
          subtitle: Text(
            '${folder.length} ${folder.length == 1 ? 'track' : 'tracks'}',
            style: TextStyle(
              fontSize: 12,
              color: context.colors.mist.withValues(alpha: 0.60),
            ),
          ),
          // The whole folder at once, without opening it.
          trailing: PopupMenuButton<String>(
            tooltip: 'Folder actions',
            icon: Icon(
              Icons.more_vert_rounded,
              color: context.colors.mist.withValues(alpha: 0.6),
            ),
            onSelected: (action) {
              final provider = context.read<MusicPlayerProvider>();
              switch (action) {
                case 'play':
                  provider.playTrack(
                    folder.items.first,
                    playlist: folder.items,
                  );
                case 'shuffle':
                  provider.shuffleAll(folder.items);
                case 'queue':
                  provider.addAllToQueue(folder.items);
                case 'playlist':
                  showAddToPlaylistSheet(context, folder.items);
              }
            },
            itemBuilder: (_) => const [
              PopupMenuItem(value: 'play', child: Text('Play')),
              PopupMenuItem(value: 'shuffle', child: Text('Shuffle')),
              PopupMenuItem(value: 'queue', child: Text('Add to queue')),
              PopupMenuItem(value: 'playlist', child: Text('Add to playlist')),
            ],
          ),
          onTap: () => Navigator.push(
            context,
            MaterialPageRoute(
              builder: (_) => FolderSongsScreen(folder: folder),
            ),
          ),
        );
      },
    );
  }

  Widget _buildPermissionDeniedView() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.folder_off,
              size: 80,
              color: context.colors.mist.withValues(alpha: 0.24),
            ),
            const SizedBox(height: 16),
            const Text(
              'Storage Permission Required',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            Text(
              'Grant permission to scan your device for local MP3, FLAC, and audio files.',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: context.colors.mist.withValues(alpha: 0.60),
              ),
            ),
            const SizedBox(height: 24),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: AppTheme.primary,
                padding: const EdgeInsets.symmetric(
                  horizontal: 24,
                  vertical: 12,
                ),
              ),
              onPressed: () => _initLocalMusic(fromButton: true),
              child: const Text(
                'Grant Access',
                style: TextStyle(color: Colors.white),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildEmptyView() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            Icons.library_music,
            size: 80,
            color: context.colors.mist.withValues(alpha: 0.24),
          ),
          SizedBox(height: 16),
          Text(
            'No Local Songs Found',
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
          ),
          SizedBox(height: 8),
          Text(
            'Add music files to your device storage to play them offline.',
            style: TextStyle(
              color: context.colors.mist.withValues(alpha: 0.60),
            ),
          ),
        ],
      ),
    );
  }
}
