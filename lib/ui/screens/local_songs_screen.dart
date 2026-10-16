import 'package:audio_service/audio_service.dart';
import 'package:cached_network_image/cached_network_image.dart';
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
import '../widgets/add_to_playlist_sheet.dart';
import '../widgets/local_artwork.dart';
import '../widgets/playing_indicator.dart';
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
    final provider = context.watch<MusicPlayerProvider>();

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
          if (_selectedTab == LocalTab.albums)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 4),
              child: OutlinedButton.icon(
                style: OutlinedButton.styleFrom(
                  backgroundColor: context.colors.lift,
                  side: BorderSide(color: context.colors.mist.withValues(alpha: 0.15)),
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 0),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                  foregroundColor: context.colors.mist,
                ),
                icon: Icon(
                  provider.localAlbumsView == 'grid' ? Icons.view_list_rounded : Icons.grid_view_rounded,
                  size: 16,
                  color: context.colors.accent,
                ),
                label: Text(
                  provider.localAlbumsView == 'grid' ? 'Show list' : 'Show grid',
                  style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
                ),
                onPressed: () {
                  final next = provider.localAlbumsView == 'grid' ? 'list' : 'grid';
                  provider.setLocalAlbumsView(next);
                },
              ),
            )
          else if (_selectedTab == LocalTab.folders)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 4),
              child: OutlinedButton.icon(
                style: OutlinedButton.styleFrom(
                  backgroundColor: context.colors.lift,
                  side: BorderSide(color: context.colors.mist.withValues(alpha: 0.15)),
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 0),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                  foregroundColor: context.colors.mist,
                ),
                icon: Icon(
                  provider.localFoldersView == 'grid' ? Icons.view_list_rounded : Icons.grid_view_rounded,
                  size: 16,
                  color: context.colors.accent,
                ),
                label: Text(
                  provider.localFoldersView == 'grid' ? 'Show list' : 'Show grid',
                  style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
                ),
                onPressed: () {
                  final next = provider.localFoldersView == 'grid' ? 'list' : 'grid';
                  provider.setLocalFoldersView(next);
                },
              ),
            )
          else if (_selectedTab == LocalTab.artists)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 4),
              child: OutlinedButton.icon(
                style: OutlinedButton.styleFrom(
                  backgroundColor: context.colors.lift,
                  side: BorderSide(color: context.colors.mist.withValues(alpha: 0.15)),
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 0),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                  foregroundColor: context.colors.mist,
                ),
                icon: Icon(
                  provider.localArtistsView == 'grid' ? Icons.view_list_rounded : Icons.grid_view_rounded,
                  size: 16,
                  color: context.colors.accent,
                ),
                label: Text(
                  provider.localArtistsView == 'grid' ? 'Show list' : 'Show grid',
                  style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
                ),
                onPressed: () {
                  final next = provider.localArtistsView == 'grid' ? 'list' : 'grid';
                  provider.setLocalArtistsView(next);
                },
              ),
            ),
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
              } else if (action == 'toggle_albums_view') {
                final next = provider.localAlbumsView == 'grid' ? 'list' : 'grid';
                provider.setLocalAlbumsView(next);
              } else if (action == 'toggle_folders_view') {
                final next = provider.localFoldersView == 'grid' ? 'list' : 'grid';
                provider.setLocalFoldersView(next);
              } else if (action == 'toggle_artists_view') {
                final next = provider.localArtistsView == 'grid' ? 'list' : 'grid';
                provider.setLocalArtistsView(next);
              }
            },
            itemBuilder: (_) => [
              if (_selectedTab == LocalTab.albums)
                PopupMenuItem(
                  value: 'toggle_albums_view',
                  child: Row(
                    children: [
                      Icon(
                        provider.localAlbumsView == 'grid' ? Icons.view_list_rounded : Icons.grid_view_rounded,
                        size: 20,
                      ),
                      const SizedBox(width: 10),
                      Text(provider.localAlbumsView == 'grid' ? 'Show list view' : 'Show grid view'),
                    ],
                  ),
                ),
              if (_selectedTab == LocalTab.folders)
                PopupMenuItem(
                  value: 'toggle_folders_view',
                  child: Row(
                    children: [
                      Icon(
                        provider.localFoldersView == 'grid' ? Icons.view_list_rounded : Icons.grid_view_rounded,
                        size: 20,
                      ),
                      const SizedBox(width: 10),
                      Text(provider.localFoldersView == 'grid' ? 'Show list view' : 'Show grid view'),
                    ],
                  ),
                ),
              if (_selectedTab == LocalTab.artists)
                PopupMenuItem(
                  value: 'toggle_artists_view',
                  child: Row(
                    children: [
                      Icon(
                        provider.localArtistsView == 'grid' ? Icons.view_list_rounded : Icons.grid_view_rounded,
                        size: 20,
                      ),
                      const SizedBox(width: 10),
                      Text(provider.localArtistsView == 'grid' ? 'Show list view' : 'Show grid view'),
                    ],
                  ),
                ),
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

    // Build Recently Played items from provider history: local songs and online songs
    final history = provider.getHistory();
    final recentSongs = <AppMediaItem>[];
    for (final song in history) {
      if (recentSongs.length >= 8) break;
      recentSongs.add(song);
    }
    for (final song in _localSongs) {
      if (recentSongs.length >= 8) break;
      if (!recentSongs.any((s) => s.id == song.id)) {
        recentSongs.add(song);
      }
    }

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

          // 2-column Grid matching the screenshot
          _buildRecentlyPlayedGrid(context, recentSongs),

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

  /// 2-column Grid matching the screenshot
  Widget _buildRecentlyPlayedGrid(
    BuildContext context,
    List<AppMediaItem> items,
  ) {
    if (items.isEmpty) return const SizedBox.shrink();

    return LayoutBuilder(
      builder: (context, constraints) {
        final columns = (constraints.maxWidth / 340).floor().clamp(2, 4);
        final rows = <Widget>[];
        for (var i = 0; i < items.length; i += columns) {
          rows.add(
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Row(
                children: [
                  for (var c = 0; c < columns; c++) ...[
                    if (c > 0) const SizedBox(width: 8),
                    Expanded(
                      child: i + c < items.length
                          ? _buildQuickPickTile(context, items[i + c], items)
                          : const SizedBox(),
                    ),
                  ],
                ],
              ),
            ),
          );
        }
        return Padding(
          padding: const EdgeInsets.fromLTRB(16, 4, 16, 4),
          child: Column(children: rows),
        );
      },
    );
  }

  Widget _buildQuickPickTile(
    BuildContext context,
    AppMediaItem item,
    List<AppMediaItem> playlist,
  ) {
    final provider = context.watch<MusicPlayerProvider>();
    final isCurrent = provider.currentTrack?.id == item.id;
    final songId = (item.extras?['songId'] as int?) ?? int.tryParse(item.id);

    final placeholder = Container(
      width: 56,
      height: 56,
      color: context.colors.lift,
      child: Icon(
        Icons.music_note_rounded,
        color: AppTheme.primary,
        size: 56 * 0.4,
      ),
    );

    return Material(
      color: context.colors.lift,
      borderRadius: BorderRadius.circular(8),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () => provider.playTrack(item, playlist: playlist),
        onLongPress: () => showTrackActions(context, item),
        child: SizedBox(
          height: 56,
          child: Row(
            children: [
              ClipRRect(
                borderRadius: BorderRadius.zero,
                child: item.artUri != null && item.artUri!.startsWith('http')
                    ? CachedNetworkImage(
                        imageUrl: item.artUri!,
                        width: 56,
                        height: 56,
                        fit: BoxFit.cover,
                        placeholder: (_, _) => placeholder,
                        errorWidget: (_, _, _) => placeholder,
                      )
                    : item.sourceType == MediaSourceType.local
                        ? LocalArtwork(
                            id: songId,
                            width: 56,
                            height: 56,
                            borderRadius: BorderRadius.zero,
                            fallback: placeholder,
                          )
                        : placeholder,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  item.title,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: isCurrent
                        ? context.colors.accent
                        : context.colors.mist,
                  ),
                ),
              ),
              const SizedBox(width: 8),
            ],
          ),
        ),
      ),
    );
  }

  List<PopupMenuEntry<String>> _buildFolderMenuItems(BuildContext context) {
    return const [
      PopupMenuItem(value: 'play', child: Text('Play folder')),
      PopupMenuItem(value: 'shuffle', child: Text('Shuffle folder')),
      PopupMenuItem(value: 'play_next', child: Text('Play next')),
      PopupMenuItem(value: 'add_to_queue', child: Text('Add to play queue')),
      PopupMenuItem(value: 'add_to_playlist', child: Text('Add to playlist')),
    ];
  }

  void _handleFolderAction(BuildContext context, String action, MediaFolder folder) {
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

    switch (action) {
      case 'play':
        provider.playTrack(folder.items.first, playlist: folder.items);
        break;
      case 'shuffle':
        provider.shuffleAll(folder.items);
        break;
      case 'play_next':
        provider.playNextAll(folder.items);
        showCompactSnack(
          messenger,
          folder.items.length == 1
              ? 'Playing next: ${folder.items.first.title}'
              : 'Playing next: ${folder.items.length} songs',
          icon: Icons.playlist_play_rounded,
        );
        break;
      case 'add_to_queue':
        provider.addAllToQueue(folder.items);
        showCompactSnack(
          messenger,
          folder.items.length == 1
              ? 'Added to queue: ${folder.items.first.title}'
              : 'Added ${folder.items.length} songs to queue',
          icon: Icons.queue_music_rounded,
        );
        break;
      case 'add_to_playlist':
        showAddToPlaylistSheet(context, folder.items);
        break;
    }
  }

  void _showFolderBottomSheet(BuildContext context, MediaFolder folder) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Theme.of(context).bottomSheetTheme.backgroundColor,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (sheetContext) => SafeArea(
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Padding(
                padding: const EdgeInsets.all(16),
                child: Text(
                  folder.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                ),
              ),
              ListTile(
                leading: Icon(Icons.play_arrow_rounded, color: sheetContext.colors.accent),
                title: const Text('Play folder'),
                onTap: () {
                  Navigator.pop(sheetContext);
                  _handleFolderAction(context, 'play', folder);
                },
              ),
              ListTile(
                leading: Icon(Icons.shuffle_rounded, color: sheetContext.colors.accent),
                title: const Text('Shuffle folder'),
                onTap: () {
                  Navigator.pop(sheetContext);
                  _handleFolderAction(context, 'shuffle', folder);
                },
              ),
              ListTile(
                leading: Icon(Icons.playlist_play_rounded, color: sheetContext.colors.accent),
                title: const Text('Play next'),
                onTap: () {
                  Navigator.pop(sheetContext);
                  _handleFolderAction(context, 'play_next', folder);
                },
              ),
              ListTile(
                leading: Icon(Icons.queue_music_rounded, color: sheetContext.colors.accent),
                title: const Text('Add to play queue'),
                onTap: () {
                  Navigator.pop(sheetContext);
                  _handleFolderAction(context, 'add_to_queue', folder);
                },
              ),
              ListTile(
                leading: Icon(Icons.playlist_add_rounded, color: sheetContext.colors.accent),
                title: const Text('Add to playlist'),
                onTap: () {
                  Navigator.pop(sheetContext);
                  _handleFolderAction(context, 'add_to_playlist', folder);
                },
              ),
            ],
          ),
        ),
      ),
    );
  }

  List<PopupMenuEntry<String>> _buildAlbumMenuItems(BuildContext context) {
    return const [
      PopupMenuItem(
        value: 'add_to_playlist',
        child: Row(
          children: [
            Icon(Icons.playlist_add_rounded, size: 20),
            SizedBox(width: 10),
            Text('Add to playlist'),
          ],
        ),
      ),
      PopupMenuItem(
        value: 'play',
        child: Row(
          children: [
            Icon(Icons.play_arrow_rounded, size: 20),
            SizedBox(width: 10),
            Text('Play album'),
          ],
        ),
      ),
      PopupMenuItem(
        value: 'shuffle',
        child: Row(
          children: [
            Icon(Icons.shuffle_rounded, size: 20),
            SizedBox(width: 10),
            Text('Shuffle album'),
          ],
        ),
      ),
      PopupMenuItem(
        value: 'play_next',
        child: Row(
          children: [
            Icon(Icons.playlist_play_rounded, size: 20),
            SizedBox(width: 10),
            Text('Play next'),
          ],
        ),
      ),
      PopupMenuItem(
        value: 'add_to_queue',
        child: Row(
          children: [
            Icon(Icons.queue_music_rounded, size: 20),
            SizedBox(width: 10),
            Text('Add to play queue'),
          ],
        ),
      ),
    ];
  }

  void _handleAlbumAction(BuildContext context, String action, LocalAlbum album) {
    final messenger = ScaffoldMessenger.of(context);
    if (album.songs.isEmpty) {
      showCompactSnack(
        messenger,
        'Album is empty',
        icon: Icons.info_outline_rounded,
      );
      return;
    }
    final provider = context.read<MusicPlayerProvider>();

    switch (action) {
      case 'add_to_playlist':
        showAddToPlaylistSheet(context, album.songs);
        break;
      case 'play':
        provider.playTrack(album.songs.first, playlist: album.songs);
        break;
      case 'shuffle':
        provider.shuffleAll(album.songs);
        break;
      case 'play_next':
        provider.playNextAll(album.songs);
        showCompactSnack(
          messenger,
          album.songs.length == 1
              ? 'Playing next: ${album.songs.first.title}'
              : 'Playing next: ${album.songs.length} songs',
          icon: Icons.playlist_play_rounded,
        );
        break;
      case 'add_to_queue':
        provider.addAllToQueue(album.songs);
        showCompactSnack(
          messenger,
          album.songs.length == 1
              ? 'Added to queue: ${album.songs.first.title}'
              : 'Added ${album.songs.length} songs to queue',
          icon: Icons.queue_music_rounded,
        );
        break;
    }
  }

  void _showAlbumBottomSheet(BuildContext context, LocalAlbum album) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Theme.of(context).bottomSheetTheme.backgroundColor,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (sheetContext) => SafeArea(
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Padding(
                padding: const EdgeInsets.all(16),
                child: Row(
                  children: [
                    LocalArtwork(
                      id: album.albumId ??
                          ((album.songs.first.extras?['songId'] as int?) ??
                              int.tryParse(album.songs.first.id)),
                      type: ArtworkType.ALBUM,
                      size: 52,
                      borderRadius: BorderRadius.circular(10),
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            album.name,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            '${album.artist} · ${album.length} ${album.length == 1 ? 'track' : 'tracks'}',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontSize: 12,
                              color: sheetContext.colors.mist.withValues(alpha: 0.6),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              const Divider(height: 1),
              ListTile(
                leading: Icon(Icons.playlist_add_rounded, color: sheetContext.colors.accent),
                title: const Text('Add to playlist'),
                subtitle: const Text('Add all songs in this album to a playlist'),
                onTap: () {
                  Navigator.pop(sheetContext);
                  _handleAlbumAction(context, 'add_to_playlist', album);
                },
              ),
              ListTile(
                leading: Icon(Icons.play_arrow_rounded, color: sheetContext.colors.accent),
                title: const Text('Play album'),
                onTap: () {
                  Navigator.pop(sheetContext);
                  _handleAlbumAction(context, 'play', album);
                },
              ),
              ListTile(
                leading: Icon(Icons.shuffle_rounded, color: sheetContext.colors.accent),
                title: const Text('Shuffle album'),
                onTap: () {
                  Navigator.pop(sheetContext);
                  _handleAlbumAction(context, 'shuffle', album);
                },
              ),
              ListTile(
                leading: Icon(Icons.playlist_play_rounded, color: sheetContext.colors.accent),
                title: const Text('Play next'),
                onTap: () {
                  Navigator.pop(sheetContext);
                  _handleAlbumAction(context, 'play_next', album);
                },
              ),
              ListTile(
                leading: Icon(Icons.queue_music_rounded, color: sheetContext.colors.accent),
                title: const Text('Add to play queue'),
                onTap: () {
                  Navigator.pop(sheetContext);
                  _handleAlbumAction(context, 'add_to_queue', album);
                },
              ),
            ],
          ),
        ),
      ),
    );
  }

  List<PopupMenuEntry<String>> _buildArtistMenuItems(BuildContext context) {
    return const [
      PopupMenuItem(
        value: 'add_to_playlist',
        child: Row(
          children: [
            Icon(Icons.playlist_add_rounded, size: 20),
            SizedBox(width: 10),
            Text('Add to playlist'),
          ],
        ),
      ),
      PopupMenuItem(
        value: 'play',
        child: Row(
          children: [
            Icon(Icons.play_arrow_rounded, size: 20),
            SizedBox(width: 10),
            Text('Play artist'),
          ],
        ),
      ),
      PopupMenuItem(
        value: 'shuffle',
        child: Row(
          children: [
            Icon(Icons.shuffle_rounded, size: 20),
            SizedBox(width: 10),
            Text('Shuffle artist'),
          ],
        ),
      ),
    ];
  }

  void _handleArtistAction(BuildContext context, String action, LocalArtist artist) {
    if (artist.songs.isEmpty) return;
    final provider = context.read<MusicPlayerProvider>();
    switch (action) {
      case 'add_to_playlist':
        showAddToPlaylistSheet(context, artist.songs);
        break;
      case 'play':
        provider.playTrack(artist.songs.first, playlist: artist.songs);
        break;
      case 'shuffle':
        provider.shuffleAll(artist.songs);
        break;
    }
  }

  void _showArtistBottomSheet(BuildContext context, LocalArtist artist) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Theme.of(context).bottomSheetTheme.backgroundColor,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (sheetContext) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.all(16),
              child: Text(
                artist.name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
              ),
            ),
            const Divider(height: 1),
            ListTile(
              leading: Icon(Icons.playlist_add_rounded, color: sheetContext.colors.accent),
              title: const Text('Add to playlist'),
              subtitle: const Text('Add all songs by this artist to a playlist'),
              onTap: () {
                Navigator.pop(sheetContext);
                _handleArtistAction(context, 'add_to_playlist', artist);
              },
            ),
            ListTile(
              leading: Icon(Icons.play_arrow_rounded, color: sheetContext.colors.accent),
              title: const Text('Play artist'),
              onTap: () {
                Navigator.pop(sheetContext);
                _handleArtistAction(context, 'play', artist);
              },
            ),
            ListTile(
              leading: Icon(Icons.shuffle_rounded, color: sheetContext.colors.accent),
              title: const Text('Shuffle artist'),
              onTap: () {
                Navigator.pop(sheetContext);
                _handleArtistAction(context, 'shuffle', artist);
              },
            ),
          ],
        ),
      ),
    );
  }


  Widget _buildNewlyAddedCard(BuildContext context, AppMediaItem song) {
    final songId = (song.extras?['songId'] as int?) ?? int.tryParse(song.id);
    final provider = context.read<MusicPlayerProvider>();

    return InkWell(
      borderRadius: BorderRadius.circular(12),
      onTap: () => provider.playTrack(song, playlist: _localSongs),
      onLongPress: () => showTrackActions(context, song),
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
    final playerProvider = context.watch<MusicPlayerProvider>();
    final isPlaying = playerProvider.isCollectionPlaying(folder.items);

    return InkWell(
      borderRadius: BorderRadius.circular(12),
      onTap: () {
        Navigator.push(
          context,
          MaterialPageRoute(builder: (_) => FolderSongsScreen(folder: folder)),
        );
      },
      onLongPress: () => _showFolderBottomSheet(context, folder),
      child: SizedBox(
        width: 115,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            AspectRatio(
              aspectRatio: 1,
              child: Stack(
                fit: StackFit.expand,
                children: [
                  CollageArtwork(
                    items: folder.items,
                    borderRadius: BorderRadius.circular(10),
                    defaultIcon: Icons.folder_rounded,
                  ),
                  if (isPlaying)
                    Container(
                      decoration: BoxDecoration(
                        color: Colors.black.withValues(alpha: 0.5),
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(color: AppTheme.primary, width: 2),
                      ),
                      child: Center(
                        child: StreamBuilder<PlaybackState>(
                          stream: playerProvider.playbackState,
                          builder: (_, snap) => PlayingIndicator(
                            isPlaying: snap.data?.playing ?? false,
                            size: 22,
                            color: AppTheme.primary,
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ),
            const SizedBox(height: 6),
            Text(
              folder.name,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontWeight: FontWeight.bold,
                fontSize: 13,
                color: isPlaying ? AppTheme.primary : null,
              ),
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
    final provider = context.watch<MusicPlayerProvider>();
    final folders = groupByFolder(_localSongs);
    final isGrid = provider.localFoldersView == 'grid';

    return RefreshIndicator(
      onRefresh: () => _initLocalMusic(forceRescan: true),
      color: context.colors.accent,
      child: isGrid
          ? _buildFoldersGrid(context, folders)
          : _buildFoldersList(context, folders),
    );
  }

  Widget _buildFoldersList(BuildContext context, List<MediaFolder> folders) {
    if (folders.isEmpty) {
      return Center(
        child: Text(
          'No folders found',
          style: TextStyle(color: context.colors.mist.withValues(alpha: 0.6)),
        ),
      );
    }
    return ListView.separated(
      padding: const EdgeInsets.fromLTRB(0, 8, 0, 110),
      itemCount: folders.length,
      separatorBuilder: (_, _) => const Divider(height: 1, indent: 76),
      itemBuilder: (context, index) {
        final folder = folders[index];
        final isSdCard = folder.path.startsWith('/storage/') &&
            !folder.path.startsWith('/storage/emulated');
        final isPlaying = context.watch<MusicPlayerProvider>().isCollectionPlaying(folder.items);

        return ListTile(
          contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
          leading: Stack(
            alignment: Alignment.center,
            children: [
              CollageArtwork(
                items: folder.items,
                size: 48,
                borderRadius: BorderRadius.circular(10),
                defaultIcon: folder.isRecordings ? Icons.mic_rounded : Icons.folder_rounded,
              ),
              if (isPlaying)
                Container(
                  width: 48,
                  height: 48,
                  decoration: BoxDecoration(
                    color: Colors.black.withValues(alpha: 0.5),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: AppTheme.primary, width: 1.5),
                  ),
                  child: Center(
                    child: StreamBuilder<PlaybackState>(
                      stream: context.read<MusicPlayerProvider>().playbackState,
                      builder: (_, snap) => PlayingIndicator(
                        isPlaying: snap.data?.playing ?? false,
                        size: 18,
                        color: AppTheme.primary,
                      ),
                    ),
                  ),
                ),
            ],
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
            onSelected: (action) => _handleFolderAction(context, action, folder),
            itemBuilder: (ctx) => _buildFolderMenuItems(ctx),
          ),
          onTap: () {
            Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => FolderSongsScreen(folder: folder)),
            );
          },
          onLongPress: () => _showFolderBottomSheet(context, folder),
        );
      },
    );
  }

  Widget _buildFoldersGrid(BuildContext context, List<MediaFolder> folders) {
    if (folders.isEmpty) {
      return Center(
        child: Text(
          'No folders found',
          style: TextStyle(color: context.colors.mist.withValues(alpha: 0.6)),
        ),
      );
    }
    return GridView.builder(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 110),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 2,
        crossAxisSpacing: 14,
        mainAxisSpacing: 14,
        childAspectRatio: 0.74,
      ),
      itemCount: folders.length,
      itemBuilder: (context, index) {
        final folder = folders[index];
        final isSdCard = folder.path.startsWith('/storage/') &&
            !folder.path.startsWith('/storage/emulated');
        final isPlaying = context.watch<MusicPlayerProvider>().isCollectionPlaying(folder.items);

        return InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: () {
            Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => FolderSongsScreen(folder: folder)),
            );
          },
          onLongPress: () => _showFolderBottomSheet(context, folder),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: AspectRatio(
                  aspectRatio: 1,
                  child: Stack(
                    fit: StackFit.expand,
                    children: [
                      CollageArtwork(
                        items: folder.items,
                        borderRadius: BorderRadius.circular(12),
                        defaultIcon: folder.isRecordings ? Icons.mic_rounded : Icons.folder_rounded,
                      ),
                      if (isPlaying)
                        Container(
                          decoration: BoxDecoration(
                            color: Colors.black.withValues(alpha: 0.5),
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(color: AppTheme.primary, width: 2),
                          ),
                          child: Center(
                            child: StreamBuilder<PlaybackState>(
                              stream: context.read<MusicPlayerProvider>().playbackState,
                              builder: (_, snap) => PlayingIndicator(
                                isPlaying: snap.data?.playing ?? false,
                                size: 24,
                                color: AppTheme.primary,
                              ),
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 8),
              Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Expanded(
                              child: Text(
                                folder.name,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                              ),
                            ),
                            if (isSdCard)
                              Container(
                                margin: const EdgeInsets.only(left: 4),
                                padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
                                decoration: BoxDecoration(
                                  color: Colors.tealAccent.withValues(alpha: 0.15),
                                  borderRadius: BorderRadius.circular(4),
                                ),
                                child: const Text(
                                  'SD',
                                  style: TextStyle(
                                    fontSize: 9,
                                    fontWeight: FontWeight.bold,
                                    color: Colors.tealAccent,
                                  ),
                                ),
                              ),
                          ],
                        ),
                        const SizedBox(height: 2),
                        Text(
                          '${folder.length} tracks',
                          style: TextStyle(
                            fontSize: 12,
                            color: context.colors.mist.withValues(alpha: 0.6),
                          ),
                        ),
                      ],
                    ),
                  ),
                  PopupMenuButton<String>(
                    padding: EdgeInsets.zero,
                    iconSize: 20,
                    icon: Icon(
                      Icons.more_vert_rounded,
                      color: context.colors.mist.withValues(alpha: 0.7),
                    ),
                    onSelected: (action) => _handleFolderAction(context, action, folder),
                    itemBuilder: (ctx) => _buildFolderMenuItems(ctx),
                  ),
                ],
              ),
            ],
          ),
        );
      },
    );
  }

  // ==========================================
  // VIEW 4: ALBUMS (Customizable Grid / List)
  // ==========================================
  Widget _buildAlbumsView(BuildContext context) {
    final provider = context.watch<MusicPlayerProvider>();
    final albums = groupByAlbum(_localSongs);
    final isGrid = provider.localAlbumsView == 'grid';

    return RefreshIndicator(
      onRefresh: () => _initLocalMusic(forceRescan: true),
      color: context.colors.accent,
      child: isGrid
          ? _buildAlbumsGrid(context, albums)
          : _buildAlbumsList(context, albums),
    );
  }

  Widget _buildAlbumsGrid(BuildContext context, List<LocalAlbum> albums) {
    if (albums.isEmpty) {
      return Center(
        child: Text(
          'No albums found',
          style: TextStyle(color: context.colors.mist.withValues(alpha: 0.6)),
        ),
      );
    }
    return GridView.builder(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 110),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 2,
        crossAxisSpacing: 14,
        mainAxisSpacing: 14,
        childAspectRatio: 0.74,
      ),
      itemCount: albums.length,
      itemBuilder: (context, index) {
        final album = albums[index];
        final artId = album.albumId ??
            ((album.songs.first.extras?['songId'] as int?) ??
                int.tryParse(album.songs.first.id));
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
          onLongPress: () => _showAlbumBottomSheet(context, album),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(12),
                  child: AspectRatio(
                    aspectRatio: 1,
                    child: LocalArtwork(
                      id: artId,
                      type: ArtworkType.ALBUM,
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 8),
              Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          album.name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          '${album.artist} · ${album.length} ${album.length == 1 ? 'track' : 'tracks'}',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 12,
                            color: context.colors.mist.withValues(alpha: 0.6),
                          ),
                        ),
                      ],
                    ),
                  ),
                  PopupMenuButton<String>(
                    padding: EdgeInsets.zero,
                    iconSize: 20,
                    icon: Icon(
                      Icons.more_vert_rounded,
                      color: context.colors.mist.withValues(alpha: 0.7),
                    ),
                    onSelected: (action) => _handleAlbumAction(context, action, album),
                    itemBuilder: (ctx) => _buildAlbumMenuItems(ctx),
                  ),
                ],
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildAlbumsList(BuildContext context, List<LocalAlbum> albums) {
    if (albums.isEmpty) {
      return Center(
        child: Text(
          'No albums found',
          style: TextStyle(color: context.colors.mist.withValues(alpha: 0.6)),
        ),
      );
    }
    return ListView.separated(
      padding: const EdgeInsets.fromLTRB(0, 8, 0, 110),
      itemCount: albums.length,
      separatorBuilder: (_, _) => const Divider(height: 1, indent: 76),
      itemBuilder: (context, index) {
        final album = albums[index];
        final artId = album.albumId ??
            ((album.songs.first.extras?['songId'] as int?) ??
                int.tryParse(album.songs.first.id));
        return ListTile(
          contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
          leading: LocalArtwork(
            id: artId,
            size: 52,
            type: ArtworkType.ALBUM,
            borderRadius: BorderRadius.circular(10),
          ),
          title: Text(
            album.name,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 15),
          ),
          subtitle: Text(
            '${album.artist} · ${album.length} ${album.length == 1 ? 'track' : 'tracks'}',
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
              color: context.colors.mist.withValues(alpha: 0.6),
            ),
            onSelected: (action) => _handleAlbumAction(context, action, album),
            itemBuilder: (ctx) => _buildAlbumMenuItems(ctx),
          ),
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
          onLongPress: () => _showAlbumBottomSheet(context, album),
        );
      },
    );
  }

  // ==========================================
  // VIEW 5: ARTISTS (Customizable List / Grid)
  // ==========================================
  Widget _buildArtistsView(BuildContext context) {
    final provider = context.watch<MusicPlayerProvider>();
    final artists = groupByArtist(_localSongs);
    final isGrid = provider.localArtistsView == 'grid';

    return RefreshIndicator(
      onRefresh: () => _initLocalMusic(forceRescan: true),
      color: context.colors.accent,
      child: isGrid
          ? _buildArtistsGrid(context, artists)
          : _buildArtistsList(context, artists),
    );
  }

  Widget _buildArtistsList(BuildContext context, List<LocalArtist> artists) {
    if (artists.isEmpty) {
      return Center(
        child: Text(
          'No artists found',
          style: TextStyle(color: context.colors.mist.withValues(alpha: 0.6)),
        ),
      );
    }
    return ListView.separated(
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
          trailing: PopupMenuButton<String>(
            icon: Icon(
              Icons.more_vert_rounded,
              color: context.colors.mist.withValues(alpha: 0.6),
            ),
            onSelected: (action) => _handleArtistAction(context, action, artist),
            itemBuilder: (ctx) => _buildArtistMenuItems(ctx),
          ),
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
          onLongPress: () => _showArtistBottomSheet(context, artist),
        );
      },
    );
  }

  Widget _buildArtistsGrid(BuildContext context, List<LocalArtist> artists) {
    if (artists.isEmpty) {
      return Center(
        child: Text(
          'No artists found',
          style: TextStyle(color: context.colors.mist.withValues(alpha: 0.6)),
        ),
      );
    }
    return GridView.builder(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 110),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 2,
        crossAxisSpacing: 14,
        mainAxisSpacing: 14,
        childAspectRatio: 0.85,
      ),
      itemCount: artists.length,
      itemBuilder: (context, index) {
        final artist = artists[index];
        return InkWell(
          borderRadius: BorderRadius.circular(16),
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
          onLongPress: () => _showArtistBottomSheet(context, artist),
          child: Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: context.colors.lift,
              borderRadius: BorderRadius.circular(16),
            ),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                CircleAvatar(
                  radius: 36,
                  backgroundColor: AppTheme.primary.withValues(alpha: 0.2),
                  child: const Icon(Icons.person_rounded, size: 36, color: AppTheme.primary),
                ),
                const SizedBox(height: 10),
                Text(
                  artist.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  textAlign: TextAlign.center,
                  style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                ),
                const SizedBox(height: 2),
                Text(
                  '${artist.length} tracks',
                  style: TextStyle(
                    fontSize: 12,
                    color: context.colors.mist.withValues(alpha: 0.6),
                  ),
                ),
              ],
            ),
          ),
        );
      },
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
