import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../providers/music_player_provider.dart';
import '../../services/desktop_tray.dart';
import '../../services/platform_bridge.dart';
import '../../services/storage_service.dart';
import '../../services/update_service.dart';
import '../../services/voice_command_service.dart';
import '../../util/playlist_codec.dart';
import 'settings_screen.dart';
import 'online_music_screen.dart';
import 'local_songs_screen.dart';
import 'podcasts_screen.dart';
import 'playlists_screen.dart';
import '../widgets/import_playlist_sheet.dart';
import '../widgets/mini_player.dart';
import '../widgets/voice_command_overlay.dart';
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
  StreamSubscription<String>? _sharedDataSubscription;
  VoiceCommandService? _voiceService;

  final List<Widget> _screens = const [
    OnlineMusicScreen(),
    LocalSongsScreen(),
    PodcastsScreen(),
    PlaylistsScreen(),
  ];

  String? _lastHandledData;
  DateTime? _lastHandledTime;

  /// The launcher icon is applied on the way out: swapping launcher entries
  /// while the app is on screen closes it on some phones.
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _checkPendingSharedData();
    } else if (state == AppLifecycleState.paused) {
      context.read<MusicPlayerProvider>().onAppBackgrounded();
      PlatformBridge.setLauncherIcon(
        dark: context.read<MusicPlayerProvider>().darkLauncherIcon,
      );
    } else if (state == AppLifecycleState.detached) {
      final provider = context.read<MusicPlayerProvider>();
      provider.saveCurrentPosition();
      if (provider.stopPlaybackOnClose) {
        provider.stop();
      }
    }
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    final provider = context.read<MusicPlayerProvider>();
    // Native parts (widget, notifications) read the icon style from their
    // own store; keep it in step with the setting on every start.
    PlatformBridge.setIconStyle(dark: provider.darkLauncherIcon);
    // This shell outlives every tab and the Now Playing route, so it is the
    // one place guaranteed to be mounted whenever playback fails.
    _errorSubscription = context
        .read<MusicPlayerProvider>()
        .playbackErrors
        .listen(_showPlaybackError);
    _initSharedDataListener();
    _checkForUpdate();
    // Windows: the notification-area icon and hide-to-tray on close.
    DesktopTray.start(context.read<MusicPlayerProvider>());
  }

  void _initSharedDataListener() {
    _sharedDataSubscription =
        PlatformBridge.sharedDataStream.listen(_handleIncomingSharedData);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _checkPendingSharedData();
    });
  }

  Future<void> _checkPendingSharedData() async {
    final initialData = await PlatformBridge.getInitialSharedData();
    if (initialData != null && initialData.isNotEmpty && mounted) {
      await _handleIncomingSharedData(initialData);
    }
  }

  Future<void> _handleIncomingSharedData(String data) async {
    if (!mounted || data.trim().isEmpty) return;
    final now = DateTime.now();
    if (_lastHandledData == data &&
        _lastHandledTime != null &&
        now.difference(_lastHandledTime!) < const Duration(seconds: 2)) {
      return;
    }
    _lastHandledData = data;
    _lastHandledTime = now;

    try {
      String content = data.trim();
      if (File(content).existsSync()) {
        content = await File(content).readAsString();
      }

      final parsed = PlaylistCodec.parseAny(content);
      if (parsed == null) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Text("Couldn't open shared playlist"),
            behavior: SnackBarBehavior.floating,
            margin: _snackMargin(context),
          ),
        );
        return;
      }

      if (!mounted) return;
      await showImportPlaylistSheet(
        context,
        initialName: parsed.name,
        items: parsed.items,
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Failed to read playlist: $e'),
          behavior: SnackBarBehavior.floating,
          margin: _snackMargin(context),
        ),
      );
    }
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
        margin: _snackMargin(context),
        action: SnackBarAction(
          label: 'Update',
          onPressed: () => showUpdateDialog(context, update),
        ),
      ),
    );
  }

  // Floating messages (already above the mini player and nav bar, which are
  // the scaffold's bottom bar): full width on a phone, a centred ~480px box
  // on a wide (desktop) window rather than a bar across the whole screen.
  static EdgeInsets _snackMargin(BuildContext context) {
    final width = MediaQuery.sizeOf(context).width;
    final side = width > 700 ? (width - 480) / 2 : 12.0;
    return EdgeInsets.only(left: side, right: side, bottom: 8);
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
          margin: _snackMargin(context),
        ),
      );
  }

  void _openVoice() {
    _voiceService ??= VoiceCommandService();
    final provider = context.read<MusicPlayerProvider>();
    VoiceCommandOverlay.show(
      context,
      service: _voiceService!,
      onCommand: (cmd) => provider.handleVoiceCommand(cmd, context),
    );
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _errorSubscription?.cancel();
    _sharedDataSubscription?.cancel();
    _voiceService?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final voiceEnabled = context
        .watch<MusicPlayerProvider>()
        .voiceControlEnabled;

    return Scaffold(
      body: Stack(
        children: [
          IndexedStack(index: _currentIndex, children: _screens),

          // Voice command mic FAB (mobile only, and only when enabled in settings)
          if (VoiceCommandService.isSupported && voiceEnabled)
            Positioned(
              right: 16,
              bottom: 16,
              child: _VoiceFab(onTap: _openVoice),
            ),
        ],
      ),
      // The mini player is part of the bottom bar, not floated over the
      // tabs: floated, it covered each list's last row and every snackbar
      // (which the scaffold puts just above its bottom bar).
      // Material 3 NavigationBar: the selection pill slides between
      // destinations, so switching tabs shows what changed instead of just
      // recolouring an icon.
      bottomNavigationBar: Column(
        mainAxisSize: MainAxisSize.min,
        children: [const MiniPlayer(), _navBar(context)],
      ),
    );
  }

  Widget _navBar(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        border: Border(
          top: BorderSide(color: context.colors.mist.withValues(alpha: 0.06)),
        ),
      ),
      child: NavigationBar(
        selectedIndex: _currentIndex,
        onDestinationSelected: (index) => setState(() => _currentIndex = index),
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
    );
  }
}

/// A small, glowing mic FAB that invites voice interaction.
class _VoiceFab extends StatefulWidget {
  final VoidCallback onTap;
  const _VoiceFab({required this.onTap});

  @override
  State<_VoiceFab> createState() => _VoiceFabState();
}

class _VoiceFabState extends State<_VoiceFab>
    with SingleTickerProviderStateMixin {
  late final AnimationController _glow;

  @override
  void initState() {
    super.initState();
    _glow = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2000),
    )..repeat(reverse: true);
  }

  @override
  void dispose() {
    _glow.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _glow,
      builder: (context, _) {
        return GestureDetector(
          onTap: widget.onTap,
          child: Container(
            width: 52,
            height: 52,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [
                  AppTheme.primary,
                  AppTheme.primary.withValues(alpha: 0.8),
                ],
              ),
              boxShadow: [
                BoxShadow(
                  color: AppTheme.primary.withValues(
                    alpha: 0.2 + _glow.value * 0.3,
                  ),
                  blurRadius: 12 + _glow.value * 8,
                  spreadRadius: _glow.value * 2,
                ),
              ],
            ),
            child: const Icon(Icons.mic_rounded, color: Colors.white, size: 24),
          ),
        );
      },
    );
  }
}
