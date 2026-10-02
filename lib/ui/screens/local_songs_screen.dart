import 'package:flutter/material.dart';
import 'package:flutter_spinkit/flutter_spinkit.dart';
import 'package:on_audio_query_pluse/on_audio_query.dart';
import 'package:provider/provider.dart';
import '../../models/local_models.dart';
import '../../models/media_folder.dart';
import '../../models/media_item_model.dart';
import '../../models/playlist.dart';
import '../../models/track_query.dart';
import '../../providers/music_player_provider.dart';
import '../theme/app_theme.dart';
import '../widgets/local_artwork.dart';
import '../widgets/selectable_track_list.dart';
import '../widgets/track_filter_bar.dart';
import '../widgets/track_tile.dart';
import '../../services/local_music_service.dart';
import 'folder_songs_screen.dart';
import 'local_collection_screen.dart';
import 'local_search_screen.dart';
import 'settings_screen.dart';

enum LocalTab {
  home('Home', Icons.dashboard_rounded),
  songs('Songs', Icons.music_note_rounded),
  folders('Folders', Icons.folder_rounded),
  albums('Albums', Icons.album_rounded),
  artists('Artists', Icons.person_rounded),
  playlists('Playlists', Icons.queue_music_rounded),
  genres('Genres', Icons.piano_rounded);

  const LocalTab(this.label, this.icon);
  final String label;
  final IconData icon;
}

class LocalSongsScreen extends StatefulWidget {
  const LocalSongsScreen({super.key});

  @override
  State<LocalSongsScreen> createState() => _LocalSongsScreenState();
}

class _LocalSongsScreenState extends State<LocalSongsScreen>
    with WidgetsBindingObserver, SingleTickerProviderStateMixin {
  final LocalMusicService _localService = LocalMusicService.instance;
  final GlobalKey<ScaffoldState> _scaffoldKey = GlobalKey<ScaffoldState>();

  List<AppMediaItem> _localSongs = [];
  bool _isLoading = true;
  bool _hasPermission = false;
  LocalScanProgress? _currentScan;

  LocalTab _selectedTab = LocalTab.home;
  late final TabController _tabController;

  String _query = '';
  TrackSort _sort = TrackSort.title;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _tabController = TabController(length: LocalTab.values.length, vsync: this);
    _tabController.addListener(() {
      if (!_tabController.indexIsChanging) {
        setState(() => _selectedTab = LocalTab.values[_tabController.index]);
      }
    });

    _localService.scanProgress.listen((progress) {
      if (mounted) {
        setState(() => _currentScan = progress);
      }
    });

    _initLocalMusic();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _tabController.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed && !_hasPermission && !_isLoading) {
      _localService.hasPermission().then((granted) {
        if (granted && mounted) _initLocalMusic();
      });
    }
  }

  Future<void> _initLocalMusic({bool forceRescan = false, bool fromButton = false}) async {
    final granted = await _localService.requestPermission(
      openSettingsIfBlocked: fromButton,
    );
    if (!mounted) return;

    if (granted) {
      setState(() {
        _hasPermission = true;
        _isLoading = _localSongs.isEmpty;
      });

      final songs = await _localService.fetchLocalSongs(forceRescan: forceRescan);
      if (mounted) {
        setState(() {
          _localSongs = songs;
          _isLoading = false;
        });
      }
    } else {
      setState(() {
        _hasPermission = false;
        _isLoading = false;
      });
    }
  }

  void _switchTab(LocalTab tab) {
    _tabController.animateTo(tab.index);
    setState(() => _selectedTab = tab);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      key: _scaffoldKey,
      drawer: _buildDrawer(context),
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.menu_rounded),
          tooltip: 'Navigation',
          onPressed: () => _scaffoldKey.currentState?.openDrawer(),
        ),
        title: Text(
          _selectedTab.label,
          style: Theme.of(context).textTheme.displaySmall,
        ),
        actions: [
          IconButton(
            icon: Icon(Icons.search_rounded, color: context.colors.accent),
            tooltip: 'Search local music',
            onPressed: () {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => LocalSearchScreen(allSongs: _localSongs),
                ),
              );
            },
          ),
          IconButton(
            icon: _currentScan?.isScanning == true
                ? SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: context.colors.accent,
                    ),
                  )
                : Icon(Icons.sync_rounded, color: context.colors.accent),
            tooltip: 'Rescan device & SD card',
            onPressed: () => _initLocalMusic(forceRescan: true),
          ),
          PopupMenuButton<String>(
            tooltip: 'More options',
            icon: Icon(Icons.more_vert_rounded, color: context.colors.accent),
            onSelected: (action) {
              if (action == 'settings') {
                Navigator.push(
                  context,
                  MaterialPageRoute(builder: (_) => const SettingsScreen()),
                );
              } else if (action == 'rescan') {
                _initLocalMusic(forceRescan: true);
              }
            },
            itemBuilder: (_) => [
              const PopupMenuItem(
                value: 'rescan',
                child: Row(
                  children: [
                    Icon(Icons.refresh_rounded, size: 20),
                    SizedBox(width: 10),
                    Text('Scan all songs (Mobile & SD)'),
                  ],
                ),
              ),
              const PopupMenuItem(
                value: 'settings',
                child: Row(
                  children: [
                    Icon(Icons.settings_outlined, size: 20),
                    SizedBox(width: 10),
                    Text('Settings'),
                  ],
                ),
              ),
            ],
          ),
        ],
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(48),
          child: _buildPillTabBar(context),
        ),
      ),
      body: _isLoading
          ? Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  SpinKitDoubleBounce(
                    color: context.colors.accent,
                    size: 50.0,
                  ),
                  const SizedBox(height: 16),
                  Text(
                    _currentScan?.message ?? 'Scanning storage & SD card...',
                    style: TextStyle(
                      color: context.colors.mist.withValues(alpha: 0.7),
                      fontSize: 14,
                    ),
                  ),
                ],
              ),
            )
          : !_hasPermission
              ? _buildPermissionDeniedView()
              : _localSongs.isEmpty
                  ? _buildEmptyView()
                  : Column(
                      children: [
                        if (_currentScan?.isScanning == true)
                          _buildScanBanner(context),
                        Expanded(
                          child: TabBarView(
                            controller: _tabController,
                            children: [
                              _buildHomeView(context),
                              _buildSongsView(context),
                              _buildFoldersView(context),
                              _buildAlbumsView(context),
                              _buildArtistsView(context),
                              _buildPlaylistsView(context),
                              _buildGenresView(context),
                            ],
                          ),
                        ),
                      ],
                    ),
    );
  }

  /// Top scrollable pill tab bar for instant category switching.
  Widget _buildPillTabBar(BuildContext context) {
    return Container(
      height: 44,
      margin: const EdgeInsets.only(bottom: 6),
      child: ListView.separated(
        padding: const EdgeInsets.symmetric(horizontal: 16),
        scrollDirection: Axis.horizontal,
        itemCount: LocalTab.values.length,
        separatorBuilder: (_, _) => const SizedBox(width: 8),
        itemBuilder: (context, index) {
          final tab = LocalTab.values[index];
          final isSelected = _selectedTab == tab;
          return ChoiceChip(
            showCheckmark: false,
            avatar: Icon(
              tab.icon,
              size: 16,
              color: isSelected ? Colors.white : context.colors.mist.withValues(alpha: 0.7),
            ),
            label: Text(tab.label),
            labelStyle: TextStyle(
              color: isSelected ? Colors.white : context.colors.mist.withValues(alpha: 0.85),
              fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
              fontSize: 13,
            ),
            selected: isSelected,
            selectedColor: AppTheme.primary,
            backgroundColor: context.colors.mist.withValues(alpha: 0.08),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
            onSelected: (_) => _switchTab(tab),
          );
        },
      ),
    );
  }

  /// Navigation Drawer matching Screenshot 2.
  Widget _buildDrawer(BuildContext context) {
    final provider = context.watch<MusicPlayerProvider>();

    return Drawer(
      child: SafeArea(
        child: Column(
          children: [
            // Drawer Header
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 20),
              decoration: BoxDecoration(
                border: Border(
                  bottom: BorderSide(
                    color: context.colors.mist.withValues(alpha: 0.1),
                  ),
                ),
              ),
              child: Row(
                children: [
                  Container(
                    width: 44,
                    height: 44,
                    decoration: BoxDecoration(
                      color: AppTheme.primary.withValues(alpha: 0.18),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: const Icon(Icons.library_music_rounded, color: AppTheme.primary),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'Local Library',
                          style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18),
                        ),
                        Text(
                          '${_localSongs.length} songs · SD & Internal',
                          style: TextStyle(
                            fontSize: 12,
                            color: context.colors.mist.withValues(alpha: 0.6),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),

            // Navigation Items
            Expanded(
              child: ListView(
                padding: const EdgeInsets.symmetric(vertical: 8),
                children: [
                  _drawerItem(
                    icon: Icons.dashboard_rounded,
                    iconColor: Colors.deepPurpleAccent,
                    title: 'Home',
                    isSelected: _selectedTab == LocalTab.home,
                    onTap: () {
                      Navigator.pop(context);
                      _switchTab(LocalTab.home);
                    },
                  ),
                  _drawerItem(
                    icon: Icons.queue_music_rounded,
                    iconColor: Colors.orangeAccent,
                    title: 'Play queue',
                    subtitle: '${provider.queue.length} in queue',
                    onTap: () {
                      Navigator.pop(context);
                      _showQueueSheet(context);
                    },
                  ),
                  _drawerItem(
                    icon: Icons.playlist_play_rounded,
                    iconColor: Colors.blueAccent,
                    title: 'Playlists',
                    isSelected: _selectedTab == LocalTab.playlists,
                    onTap: () {
                      Navigator.pop(context);
                      _switchTab(LocalTab.playlists);
                    },
                  ),
                  _drawerItem(
                    icon: Icons.person_rounded,
                    iconColor: Colors.redAccent,
                    title: 'Artists',
                    isSelected: _selectedTab == LocalTab.artists,
                    onTap: () {
                      Navigator.pop(context);
                      _switchTab(LocalTab.artists);
                    },
                  ),
                  _drawerItem(
                    icon: Icons.album_rounded,
                    iconColor: Colors.tealAccent,
                    title: 'Albums',
                    isSelected: _selectedTab == LocalTab.albums,
                    onTap: () {
                      Navigator.pop(context);
                      _switchTab(LocalTab.albums);
                    },
                  ),
                  _drawerItem(
                    icon: Icons.music_note_rounded,
                    iconColor: Colors.amberAccent,
                    title: 'Songs',
                    isSelected: _selectedTab == LocalTab.songs,
                    onTap: () {
                      Navigator.pop(context);
                      _switchTab(LocalTab.songs);
                    },
                  ),
                  _drawerItem(
                    icon: Icons.piano_rounded,
                    iconColor: Colors.purpleAccent,
                    title: 'Genres',
                    isSelected: _selectedTab == LocalTab.genres,
                    onTap: () {
                      Navigator.pop(context);
                      _switchTab(LocalTab.genres);
                    },
                  ),
                  _drawerItem(
                    icon: Icons.folder_rounded,
                    iconColor: Colors.yellow.shade700,
                    title: 'Folders',
                    isSelected: _selectedTab == LocalTab.folders,
                    onTap: () {
                      Navigator.pop(context);
                      _switchTab(LocalTab.folders);
                    },
                  ),
                  const Divider(height: 24),
                  _drawerItem(
                    icon: Icons.sync_rounded,
                    iconColor: context.colors.accent,
                    title: 'Scan Device & SD Card',
                    onTap: () {
                      Navigator.pop(context);
                      _initLocalMusic(forceRescan: true);
                    },
                  ),
                  _drawerItem(
                    icon: Icons.settings_rounded,
                    iconColor: context.colors.mist.withValues(alpha: 0.7),
                    title: 'Settings',
                    onTap: () {
                      Navigator.pop(context);
                      Navigator.push(
                        context,
                        MaterialPageRoute(builder: (_) => const SettingsScreen()),
                      );
                    },
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _drawerItem({
    required IconData icon,
    required Color iconColor,
    required String title,
    String? subtitle,
    bool isSelected = false,
    required VoidCallback onTap,
  }) {
    return ListTile(
      leading: Icon(icon, color: iconColor, size: 24),
      title: Text(
        title,
        style: TextStyle(
          fontWeight: isSelected ? FontWeight.bold : FontWeight.w500,
          color: isSelected ? AppTheme.primary : null,
        ),
      ),
      subtitle: subtitle != null
          ? Text(subtitle, style: const TextStyle(fontSize: 12))
          : null,
      selected: isSelected,
      selectedTileColor: AppTheme.primary.withValues(alpha: 0.12),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 2),
      onTap: onTap,
    );
  }

  Widget _buildScanBanner(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      color: AppTheme.primary.withValues(alpha: 0.15),
      child: Row(
        children: [
          SizedBox(
            width: 14,
            height: 14,
            child: CircularProgressIndicator(
              strokeWidth: 2,
              color: context.colors.accent,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              _currentScan?.message ?? 'Scanning...',
              style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w500),
            ),
          ),
          if (_currentScan != null)
            Text(
              '${_currentScan!.count} found',
              style: TextStyle(
                fontSize: 12,
                color: context.colors.accent,
                fontWeight: FontWeight.bold,
              ),
            ),
        ],
      ),
    );
  }

  // ==========================================
  // VIEW 1: HOME (Reference Screenshot 1)
  // ==========================================
  Widget _buildHomeView(BuildContext context) {
    final provider = context.watch<MusicPlayerProvider>();
    final folders = groupByFolder(_localSongs);
    final newlyAdded = getNewlyAdded(_localSongs, limit: 15);

    // Build Recently Played items from provider history: local songs, folders, and newly added
    final history = provider.getHistory().where((s) => s.sourceType == MediaSourceType.local).toList();
    final recentSongs = history.isNotEmpty ? history.take(6).toList() : _localSongs.take(6).toList();

    return RefreshIndicator(
      onRefresh: () => _initLocalMusic(forceRescan: true),
      color: context.colors.accent,
      child: ListView(
        padding: const EdgeInsets.only(bottom: 110),
        children: [
          // Section: Recently played
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text(
                  'Recently played',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                ),
                TextButton(
                  onPressed: () => _switchTab(LocalTab.songs),
                  child: const Text('See all'),
                ),
              ],
            ),
          ),

          // 3-column Grid matching Screenshot 1
          _buildRecentlyPlayedGrid(context, recentSongs, folders),

          const SizedBox(height: 16),

          // Section: Newly added (Screenshot 1)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text(
                  'Newly added',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                ),
                TextButton(
                  onPressed: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => LocalCollectionScreen(
                          title: 'Newly added',
                          subtitle: 'Latest tracks added to storage',
                          songs: getNewlyAdded(_localSongs, limit: 100),
                          fallbackIcon: Icons.new_releases_rounded,
                        ),
                      ),
                    );
                  },
                  child: const Text('See all'),
                ),
              ],
            ),
          ),

          // Horizontal scrolling row matching Screenshot 1
          SizedBox(
            height: 165,
            child: ListView.separated(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              scrollDirection: Axis.horizontal,
              itemCount: newlyAdded.length,
              separatorBuilder: (_, _) => const SizedBox(width: 12),
              itemBuilder: (context, index) {
                final song = newlyAdded[index];
                return _buildNewlyAddedCard(context, song);
              },
            ),
          ),

          const SizedBox(height: 20),

          // Section: Folders preview
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text(
                  'Folders',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                ),
                TextButton(
                  onPressed: () => _switchTab(LocalTab.folders),
                  child: const Text('See all'),
                ),
              ],
            ),
          ),

          SizedBox(
            height: 160,
            child: ListView.separated(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              scrollDirection: Axis.horizontal,
              itemCount: folders.take(8).length,
              separatorBuilder: (_, _) => const SizedBox(width: 12),
              itemBuilder: (context, index) {
                final folder = folders[index];
                return _buildFolderCard(context, folder);
              },
            ),
          ),
        ],
      ),
    );
  }

  /// 3-column Grid matching Screenshot 1
  Widget _buildRecentlyPlayedGrid(
    BuildContext context,
    List<AppMediaItem> songs,
    List<MediaFolder> folders,
  ) {
    // Combine songs, folders, and playlist cards for the rich Musicolet look
    final cards = <Widget>[];

    for (var i = 0; i < songs.length && i < 4; i++) {
      cards.add(_buildSongGridCard(context, songs[i]));
    }

    if (folders.isNotEmpty) {
      cards.add(_buildFolderGridCard(context, folders.first));
    }

    if (folders.length > 1) {
      cards.add(_buildFolderGridCard(context, folders[1]));
    }

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: GridView.count(
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        crossAxisCount: 3,
        crossAxisSpacing: 10,
        mainAxisSpacing: 12,
        childAspectRatio: 0.68,
        children: cards.take(6).toList(),
      ),
    );
  }

  Widget _buildSongGridCard(BuildContext context, AppMediaItem song) {
    final provider = context.watch<MusicPlayerProvider>();
    final isPlaying = provider.currentTrack?.id == song.id;
    final songId = (song.extras?['songId'] as int?) ?? int.tryParse(song.id);

    return InkWell(
      borderRadius: BorderRadius.circular(12),
      onTap: () => provider.playTrack(song, playlist: _localSongs),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Square Artwork
          Stack(
            children: [
              AspectRatio(
                aspectRatio: 1,
                child: LocalArtwork(
                  id: songId,
                  borderRadius: BorderRadius.circular(10),
                ),
              ),
              if (isPlaying)
                Positioned(
                  bottom: 6,
                  left: 6,
                  child: Container(
                    padding: const EdgeInsets.all(4),
                    decoration: BoxDecoration(
                      color: Colors.black.withValues(alpha: 0.65),
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(Icons.pause_rounded, size: 14, color: Colors.white),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 6),
          // Title & Menu Row
          Row(
            children: [
              Expanded(
                child: Text(
                  song.title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                ),
              ),
              GestureDetector(
                onTap: () => showTrackActions(context, song),
                child: Icon(
                  Icons.more_vert_rounded,
                  size: 16,
                  color: context.colors.mist.withValues(alpha: 0.5),
                ),
              ),
            ],
          ),
          Text(
            song.artist,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: 11,
              color: context.colors.mist.withValues(alpha: 0.6),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildFolderGridCard(BuildContext context, MediaFolder folder) {
    final provider = context.read<MusicPlayerProvider>();

    return InkWell(
      borderRadius: BorderRadius.circular(12),
      onTap: () {
        Navigator.push(
          context,
          MaterialPageRoute(builder: (_) => FolderSongsScreen(folder: folder)),
        );
      },
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 2x2 Collage Artwork for Folder (Screenshot 1)
          AspectRatio(
            aspectRatio: 1,
            child: CollageArtwork(
              items: folder.items,
              borderRadius: BorderRadius.circular(10),
              defaultIcon: Icons.folder_rounded,
            ),
          ),
          const SizedBox(height: 6),
          Row(
            children: [
              Expanded(
                child: Text(
                  folder.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                ),
              ),
              GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTapDown: (details) {
                  final offset = details.globalPosition;
                  showMenu<String>(
                    context: context,
                    position: RelativeRect.fromLTRB(
                      offset.dx,
                      offset.dy,
                      offset.dx + 1,
                      offset.dy + 1,
                    ),
                    items: const [
                      PopupMenuItem(value: 'play', child: Text('Play folder')),
                      PopupMenuItem(value: 'shuffle', child: Text('Shuffle folder')),
                    ],
                  ).then((action) {
                    if (action == 'play' && folder.items.isNotEmpty) {
                      provider.playTrack(folder.items.first, playlist: folder.items);
                    } else if (action == 'shuffle' && folder.items.isNotEmpty) {
                      provider.shuffleAll(folder.items);
                    }
                  });
                },
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 2, vertical: 2),
                  child: Icon(
                    Icons.more_vert_rounded,
                    size: 16,
                    color: context.colors.mist.withValues(alpha: 0.5),
                  ),
                ),
              ),
            ],
          ),
          Text(
            'Folder',
            style: TextStyle(
              fontSize: 11,
              color: context.colors.mist.withValues(alpha: 0.6),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildNewlyAddedCard(BuildContext context, AppMediaItem song) {
    final songId = (song.extras?['songId'] as int?) ?? int.tryParse(song.id);
    final provider = context.read<MusicPlayerProvider>();

    return InkWell(
      borderRadius: BorderRadius.circular(12),
      onTap: () => provider.playTrack(song, playlist: _localSongs),
      child: SizedBox(
        width: 110,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            AspectRatio(
              aspectRatio: 1,
              child: LocalArtwork(
                id: songId,
                borderRadius: BorderRadius.circular(10),
              ),
            ),
            const SizedBox(height: 6),
            Text(
              song.title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
            ),
            Text(
              song.artist,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 11,
                color: context.colors.mist.withValues(alpha: 0.6),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildFolderCard(BuildContext context, MediaFolder folder) {
    return InkWell(
      borderRadius: BorderRadius.circular(12),
      onTap: () {
        Navigator.push(
          context,
          MaterialPageRoute(builder: (_) => FolderSongsScreen(folder: folder)),
        );
      },
      child: SizedBox(
        width: 115,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            AspectRatio(
              aspectRatio: 1,
              child: CollageArtwork(
                items: folder.items,
                borderRadius: BorderRadius.circular(10),
                defaultIcon: Icons.folder_rounded,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              folder.name,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
            ),
            Text(
              '${folder.length} tracks',
              style: TextStyle(
                fontSize: 11,
                color: context.colors.mist.withValues(alpha: 0.6),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ==========================================
  // VIEW 2: SONGS (Full List + Search + Sort)
  // ==========================================
  Widget _buildSongsView(BuildContext context) {
    final filtered = sortTracks(filterTracks(_localSongs, _query), _sort);

    return Column(
      children: [
        TrackFilterBar(
          query: _query,
          onQueryChanged: (value) => setState(() => _query = value),
          sort: _sort,
          onSortChanged: (value) => setState(() => _sort = value),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 6),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                _query.isEmpty
                    ? '${_localSongs.length} Songs found'
                    : '${filtered.length} of ${_localSongs.length}',
                style: TextStyle(color: context.colors.mist.withValues(alpha: 0.65)),
              ),
              const Spacer(),
              IconButton(
                tooltip: 'Shuffle',
                icon: Icon(Icons.shuffle_rounded, color: context.colors.accent),
                onPressed: filtered.isEmpty
                    ? null
                    : () => context.read<MusicPlayerProvider>().shuffleAll(filtered),
              ),
              ElevatedButton.icon(
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppTheme.primary,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                ),
                icon: const Icon(Icons.play_arrow, color: Colors.white),
                label: const Text('Play All', style: TextStyle(color: Colors.white)),
                onPressed: filtered.isEmpty
                    ? null
                    : () => context.read<MusicPlayerProvider>().playTrack(
                          filtered.first,
                          playlist: filtered,
                        ),
              ),
            ],
          ),
        ),
        Expanded(
          child: RefreshIndicator(
            onRefresh: () => _initLocalMusic(forceRescan: true),
            color: context.colors.accent,
            child: filtered.isEmpty
                ? Center(
                    child: Text(
                      'No songs match your search.',
                      style: TextStyle(color: context.colors.mist.withValues(alpha: 0.54)),
                    ),
                  )
                : SelectableTrackList(songs: filtered),
          ),
        ),
      ],
    );
  }

  // ==========================================
  // VIEW 3: FOLDERS (Device & SD Card directories)
  // ==========================================
  Widget _buildFoldersView(BuildContext context) {
    final folders = groupByFolder(_localSongs);

    return RefreshIndicator(
      onRefresh: () => _initLocalMusic(forceRescan: true),
      color: context.colors.accent,
      child: ListView.separated(
        padding: const EdgeInsets.fromLTRB(0, 8, 0, 110),
        itemCount: folders.length,
        separatorBuilder: (_, _) => const Divider(height: 1, indent: 76),
        itemBuilder: (context, index) {
          final folder = folders[index];
          final isSdCard = folder.path.startsWith('/storage/') &&
              !folder.path.startsWith('/storage/emulated');

          return ListTile(
            contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
            leading: CollageArtwork(
              items: folder.items,
              size: 48,
              borderRadius: BorderRadius.circular(10),
              defaultIcon: folder.isRecordings ? Icons.mic_rounded : Icons.folder_rounded,
            ),
            title: Row(
              children: [
                Expanded(
                  child: Text(
                    folder.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontWeight: FontWeight.w600),
                  ),
                ),
                if (isSdCard)
                  Container(
                    margin: const EdgeInsets.only(left: 6),
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                    decoration: BoxDecoration(
                      color: Colors.tealAccent.withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: const Text(
                      'SD Card',
                      style: TextStyle(
                        fontSize: 10,
                        fontWeight: FontWeight.bold,
                        color: Colors.tealAccent,
                      ),
                    ),
                  ),
              ],
            ),
            subtitle: Text(
              '${folder.length} tracks · ${folder.path}',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 12,
                color: context.colors.mist.withValues(alpha: 0.55),
              ),
            ),
            trailing: PopupMenuButton<String>(
              icon: Icon(
                Icons.more_vert_rounded,
                color: context.colors.mist.withValues(alpha: 0.5),
              ),
              onSelected: (action) {
                final provider = context.read<MusicPlayerProvider>();
                if (action == 'play' && folder.items.isNotEmpty) {
                  provider.playTrack(folder.items.first, playlist: folder.items);
                } else if (action == 'shuffle' && folder.items.isNotEmpty) {
                  provider.shuffleAll(folder.items);
                }
              },
              itemBuilder: (_) => [
                const PopupMenuItem(value: 'play', child: Text('Play folder')),
                const PopupMenuItem(value: 'shuffle', child: Text('Shuffle folder')),
              ],
            ),
            onTap: () {
              Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => FolderSongsScreen(folder: folder)),
              );
            },
          );
        },
      ),
    );
  }

  // ==========================================
  // VIEW 4: ALBUMS
  // ==========================================
  Widget _buildAlbumsView(BuildContext context) {
    final albums = groupByAlbum(_localSongs);

    return RefreshIndicator(
      onRefresh: () => _initLocalMusic(forceRescan: true),
      color: context.colors.accent,
      child: GridView.builder(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 110),
        gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: 2,
          crossAxisSpacing: 14,
          mainAxisSpacing: 14,
          childAspectRatio: 0.78,
        ),
        itemCount: albums.length,
        itemBuilder: (context, index) {
          final album = albums[index];
          return InkWell(
            borderRadius: BorderRadius.circular(12),
            onTap: () {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => LocalCollectionScreen(
                    title: album.name,
                    subtitle: album.artist,
                    songs: album.songs,
                    artworkId: album.albumId,
                    fallbackIcon: Icons.album_rounded,
                  ),
                ),
              );
            },
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                AspectRatio(
                  aspectRatio: 1,
                  child: LocalArtwork(
                    id: album.albumId ??
                        ((album.songs.first.extras?['songId'] as int?) ??
                            int.tryParse(album.songs.first.id)),
                    type: ArtworkType.ALBUM,
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  album.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                ),
                Text(
                  '${album.artist} · ${album.length} tracks',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 12,
                    color: context.colors.mist.withValues(alpha: 0.6),
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  // ==========================================
  // VIEW 5: ARTISTS
  // ==========================================
  Widget _buildArtistsView(BuildContext context) {
    final artists = groupByArtist(_localSongs);

    return RefreshIndicator(
      onRefresh: () => _initLocalMusic(forceRescan: true),
      color: context.colors.accent,
      child: ListView.separated(
        padding: const EdgeInsets.fromLTRB(0, 8, 0, 110),
        itemCount: artists.length,
        separatorBuilder: (_, _) => const Divider(height: 1, indent: 76),
        itemBuilder: (context, index) {
          final artist = artists[index];
          return ListTile(
            contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
            leading: CircleAvatar(
              radius: 24,
              backgroundColor: AppTheme.primary.withValues(alpha: 0.2),
              child: const Icon(Icons.person_rounded, color: AppTheme.primary),
            ),
            title: Text(
              artist.name,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontWeight: FontWeight.w600),
            ),
            subtitle: Text(
              '${artist.length} ${artist.length == 1 ? 'song' : 'songs'} · ${artist.albumCount} ${artist.albumCount == 1 ? 'album' : 'albums'}',
              style: TextStyle(
                fontSize: 12,
                color: context.colors.mist.withValues(alpha: 0.6),
              ),
            ),
            trailing: const Icon(Icons.chevron_right_rounded),
            onTap: () {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => LocalCollectionScreen(
                    title: artist.name,
                    subtitle: '${artist.length} tracks',
                    songs: artist.songs,
                    fallbackIcon: Icons.person_rounded,
                  ),
                ),
              );
            },
          );
        },
      ),
    );
  }

  // ==========================================
  // VIEW 6: PLAYLISTS
  // ==========================================
  Widget _buildPlaylistsView(BuildContext context) {
    final provider = context.watch<MusicPlayerProvider>();
    final newlyAdded = getNewlyAdded(_localSongs, limit: 50);
    final history = provider.getHistory().where((s) => s.sourceType == MediaSourceType.local).toList();
    final customPlaylists = provider.getPlaylists();

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 110),
      children: [
        // Smart Playlists
        _buildPlaylistTile(
          context,
          title: 'Recently played',
          subtitle: '${history.length} songs',
          items: history.isNotEmpty ? history : _localSongs.take(20).toList(),
          icon: Icons.history_rounded,
        ),
        const SizedBox(height: 12),
        _buildPlaylistTile(
          context,
          title: 'Newly added',
          subtitle: '${newlyAdded.length} songs',
          items: newlyAdded,
          icon: Icons.new_releases_rounded,
        ),
        const SizedBox(height: 12),
        _buildPlaylistTile(
          context,
          title: 'Favorites',
          subtitle: '${provider.getFavorites().length} songs',
          items: provider.getFavorites(),
          icon: Icons.favorite_rounded,
        ),

        if (customPlaylists.isNotEmpty) ...[
          const Padding(
            padding: EdgeInsets.fromLTRB(4, 20, 4, 10),
            child: Text(
              'Your playlists',
              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
            ),
          ),
          ...customPlaylists.map(
            (pl) => Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: _buildCustomPlaylistTile(context, pl),
            ),
          ),
        ],
      ],
    );
  }

  Widget _buildPlaylistTile(
    BuildContext context, {
    required String title,
    required String subtitle,
    required List<AppMediaItem> items,
    required IconData icon,
  }) {
    return ListTile(
      tileColor: context.colors.mist.withValues(alpha: 0.05),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
      leading: CollageArtwork(
        items: items,
        size: 52,
        borderRadius: BorderRadius.circular(10),
        defaultIcon: icon,
      ),
      title: Text(title, style: const TextStyle(fontWeight: FontWeight.bold)),
      subtitle: Text(
        subtitle,
        style: TextStyle(fontSize: 12, color: context.colors.mist.withValues(alpha: 0.6)),
      ),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          IconButton(
            icon: Icon(Icons.play_circle_filled_rounded, color: context.colors.accent, size: 30),
            onPressed: items.isEmpty
                ? null
                : () => context.read<MusicPlayerProvider>().playTrack(items.first, playlist: items),
          ),
        ],
      ),
      onTap: () {
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => LocalCollectionScreen(
              title: title,
              subtitle: subtitle,
              songs: items,
              fallbackIcon: icon,
            ),
          ),
        );
      },
    );
  }

  Widget _buildCustomPlaylistTile(BuildContext context, Playlist playlist) {
    return ListTile(
      tileColor: context.colors.mist.withValues(alpha: 0.05),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
      leading: CollageArtwork(
        items: playlist.items,
        size: 52,
        borderRadius: BorderRadius.circular(10),
        defaultIcon: Icons.queue_music_rounded,
      ),
      title: Text(playlist.name, style: const TextStyle(fontWeight: FontWeight.bold)),
      subtitle: Text(
        '${playlist.length} songs',
        style: TextStyle(fontSize: 12, color: context.colors.mist.withValues(alpha: 0.6)),
      ),
      trailing: IconButton(
        icon: Icon(Icons.play_circle_filled_rounded, color: context.colors.accent, size: 30),
        onPressed: playlist.items.isEmpty
            ? null
            : () => context.read<MusicPlayerProvider>().playTrack(playlist.items.first, playlist: playlist.items),
      ),
      onTap: () {
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => LocalCollectionScreen(
              title: playlist.name,
              subtitle: '${playlist.length} songs',
              songs: playlist.items,
              fallbackIcon: Icons.queue_music_rounded,
            ),
          ),
        );
      },
    );
  }

  // ==========================================
  // VIEW 7: GENRES
  // ==========================================
  Widget _buildGenresView(BuildContext context) {
    final genres = groupByGenre(_localSongs);

    return RefreshIndicator(
      onRefresh: () => _initLocalMusic(forceRescan: true),
      color: context.colors.accent,
      child: ListView.separated(
        padding: const EdgeInsets.fromLTRB(0, 8, 0, 110),
        itemCount: genres.length,
        separatorBuilder: (_, _) => const Divider(height: 1, indent: 76),
        itemBuilder: (context, index) {
          final genre = genres[index];
          return ListTile(
            leading: CircleAvatar(
              radius: 22,
              backgroundColor: Colors.purpleAccent.withValues(alpha: 0.15),
              child: const Icon(Icons.piano_rounded, color: Colors.purpleAccent),
            ),
            title: Text(genre.name, style: const TextStyle(fontWeight: FontWeight.w600)),
            subtitle: Text('${genre.length} tracks'),
            trailing: const Icon(Icons.chevron_right_rounded),
            onTap: () {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => LocalCollectionScreen(
                    title: genre.name,
                    subtitle: '${genre.length} tracks',
                    songs: genre.songs,
                    fallbackIcon: Icons.piano_rounded,
                  ),
                ),
              );
            },
          );
        },
      ),
    );
  }

  void _showQueueSheet(BuildContext context) {
    final provider = context.read<MusicPlayerProvider>();
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (sheetContext) => DraggableScrollableSheet(
        initialChildSize: 0.65,
        minChildSize: 0.4,
        maxChildSize: 0.9,
        expand: false,
        builder: (_, scrollController) => Column(
          children: [
            Container(
              margin: const EdgeInsets.symmetric(vertical: 10),
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: Colors.white24,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text(
                    'Play Queue',
                    style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18),
                  ),
                  Text(
                    '${provider.queue.length} songs',
                    style: TextStyle(color: context.colors.mist.withValues(alpha: 0.6)),
                  ),
                ],
              ),
            ),
            const Divider(height: 1),
            Expanded(
              child: provider.queue.isEmpty
                  ? const Center(child: Text('Queue is empty'))
                  : SelectableTrackList(songs: provider.queue),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildPermissionDeniedView() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.folder_off_rounded, size: 70, color: Colors.orangeAccent),
            const SizedBox(height: 16),
            const Text(
              'Storage Permission Required',
              style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            Text(
              'Pulse needs permission to scan your phone and SD card for music files.',
              textAlign: TextAlign.center,
              style: TextStyle(color: context.colors.mist.withValues(alpha: 0.7)),
            ),
            const SizedBox(height: 24),
            ElevatedButton.icon(
              style: ElevatedButton.styleFrom(
                backgroundColor: AppTheme.primary,
                padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              ),
              icon: const Icon(Icons.lock_open_rounded, color: Colors.white),
              label: const Text('Grant Access', style: TextStyle(color: Colors.white)),
              onPressed: () => _initLocalMusic(fromButton: true),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildEmptyView() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.music_off_rounded, size: 70, color: Colors.grey),
            const SizedBox(height: 16),
            const Text(
              'No Local Songs Found',
              style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            Text(
              'No audio files were detected on your internal storage or SD card.',
              textAlign: TextAlign.center,
              style: TextStyle(color: context.colors.mist.withValues(alpha: 0.7)),
            ),
            const SizedBox(height: 20),
            ElevatedButton.icon(
              icon: const Icon(Icons.refresh_rounded),
              label: const Text('Scan Again'),
              onPressed: () => _initLocalMusic(forceRescan: true),
            ),
          ],
        ),
      ),
    );
  }
}
