import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../providers/music_player_provider.dart';
import '../../services/platform_bridge.dart';
import '../../services/storage_service.dart';
import '../../services/update_service.dart';
import 'settings_screen.dart';
import 'online_music_screen.dart';
import 'local_songs_screen.dart';
import 'podcasts_screen.dart';
import 'playlists_screen.dart';
import '../widgets/mini_player.dart';
import '../theme/app_theme.dart';

class MainNavigationScreen extends StatefulWidget {
  const MainNavigationScreen({super.key});

  @override
  State<MainNavigationScreen> createState() => _MainNavigationScreenState();
}

class _MainNavigationScreenState extends State<MainNavigationScreen>
    with WidgetsBindingObserver {
  int _currentIndex = 0;
  StreamSubscription<String>? _errorSubscription;

  final List<Widget> _screens = const [
    OnlineMusicScreen(),
    LocalSongsScreen(),
    PodcastsScreen(),
    PlaylistsScreen(),
  ];

  /// The launcher icon is applied on the way out: swapping launcher entries
  /// while the app is on screen closes it on some phones.
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused) {
      PlatformBridge.setLauncherIcon(
        dark: context.read<MusicPlayerProvider>().darkLauncherIcon,
      );
    }
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    // Native parts (widget, notifications) read the icon style from their
    // own store; keep it in step with the setting on every start.
    PlatformBridge.setIconStyle(
      dark: context.read<MusicPlayerProvider>().darkLauncherIcon,
    );
    // This shell outlives every tab and the Now Playing route, so it is the
    // one place guaranteed to be mounted whenever playback fails.
    _errorSubscription = context
        .read<MusicPlayerProvider>()
        .playbackErrors
        .listen(_showPlaybackError);
    _checkForUpdate();
  }

  /// Once a day, quietly: a newer release only shows as a SnackBar.
  Future<void> _checkForUpdate() async {
    // Off Android (tests) there's no version to compare: skip, and write
    // nothing.
    if (await PlatformBridge.appVersion() == null) return;
    if (!await StorageService().updateCheckDue()) return;
    final update = await UpdateService.check();
    if (update == null || !mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('Pulse ${update.version} is available'),
        behavior: SnackBarBehavior.floating,
        margin: const EdgeInsets.only(left: 12, right: 12, bottom: 140),
        action: SnackBarAction(
          label: 'Update',
          onPressed: () => showUpdateDialog(context, update),
        ),
      ),
    );
  }

  void _showPlaybackError(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text(message, maxLines: 2, overflow: TextOverflow.ellipsis),
          backgroundColor: Colors.redAccent,
          behavior: SnackBarBehavior.floating,
          margin: const EdgeInsets.only(left: 12, right: 12, bottom: 140),
        ),
      );
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _errorSubscription?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Stack(
        children: [
          IndexedStack(index: _currentIndex, children: _screens),

          // Floating MiniPlayer resting above bottom navigation bar
          const Positioned(left: 0, right: 0, bottom: 0, child: MiniPlayer()),
        ],
      ),
      // Material 3 NavigationBar: the selection pill slides between
      // destinations, so switching tabs shows what changed instead of just
      // recolouring an icon.
      bottomNavigationBar: DecoratedBox(
        decoration: BoxDecoration(
          border: Border(
            top: BorderSide(color: context.colors.mist.withValues(alpha: 0.06)),
          ),
        ),
        child: NavigationBar(
          selectedIndex: _currentIndex,
          onDestinationSelected: (index) =>
              setState(() => _currentIndex = index),
          destinations: const [
            NavigationDestination(
              icon: Icon(Icons.explore_outlined),
              selectedIcon: Icon(Icons.explore_rounded),
              label: 'Online',
            ),
            NavigationDestination(
              icon: Icon(Icons.folder_outlined),
              selectedIcon: Icon(Icons.folder_rounded),
              label: 'Local',
            ),
            NavigationDestination(
              icon: Icon(Icons.podcasts_outlined),
              selectedIcon: Icon(Icons.podcasts_rounded),
              label: 'Podcasts',
            ),
            NavigationDestination(
              icon: Icon(Icons.library_music_outlined),
              selectedIcon: Icon(Icons.library_music_rounded),
              label: 'Library',
            ),
          ],
        ),
      ),
    );
  }
}
