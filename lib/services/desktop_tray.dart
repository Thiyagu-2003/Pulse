import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:tray_manager/tray_manager.dart';
import 'package:window_manager/window_manager.dart';

import '../providers/music_player_provider.dart';

/// Windows: Pulse lives in the taskbar's notification area (the "show hidden
/// icons" tray). Closing the window hides it there and the music keeps
/// playing; the tray icon brings it back, and its menu plays, pauses, skips
/// or quits.
class DesktopTray with TrayListener, WindowListener {
  DesktopTray._(this._provider);

  final MusicPlayerProvider _provider;
  static DesktopTray? _instance;

  /// Once per run; a no-op off Windows.
  static Future<void> start(MusicPlayerProvider provider) async {
    if (!Platform.isWindows || _instance != null) return;
    final tray = _instance = DesktopTray._(provider);
    try {
      await windowManager.ensureInitialized();
      // The ✕ button hides to the tray instead of ending playback.
      await windowManager.setPreventClose(true);
      windowManager.addListener(tray);
      await trayManager.setIcon('icons/tray_icon.ico');
      trayManager.addListener(tray);
      await tray._update();
      // Title and play/pause label follow the song.
      provider.addListener(tray._update);
      provider.playbackState
          .map((s) => s.playing)
          .distinct()
          .listen((_) => tray._update());
    } catch (e) {
      debugPrint('Tray unavailable: $e');
    }
  }

  String? _shownTitle;
  bool? _shownPlaying;

  Future<void> _update() async {
    final track = _provider.currentTrack;
    final playing = _provider.audioHandler.playbackState.value.playing;
    final title = track == null ? null : '${track.title} – ${track.artist}';
    if (title == _shownTitle && playing == _shownPlaying) return;
    _shownTitle = title;
    _shownPlaying = playing;
    // Windows cuts tray tooltips at 127 characters.
    final tip = title == null ? 'Pulse' : 'Pulse · $title';
    await trayManager.setToolTip(
      tip.length > 120 ? '${tip.substring(0, 117)}…' : tip,
    );
    await trayManager.setContextMenu(
      Menu(
        items: [
          MenuItem(key: 'show', label: 'Open Pulse'),
          MenuItem.separator(),
          MenuItem(
            key: 'play',
            label: playing ? 'Pause' : 'Play',
            disabled: track == null,
          ),
          MenuItem(key: 'next', label: 'Next', disabled: track == null),
          MenuItem(key: 'previous', label: 'Previous', disabled: track == null),
          MenuItem.separator(),
          MenuItem(key: 'quit', label: 'Quit Pulse'),
        ],
      ),
    );
  }

  Future<void> _showWindow() async {
    await windowManager.show();
    await windowManager.focus();
  }

  @override
  void onTrayIconMouseDown() => _showWindow();

  @override
  void onTrayIconRightMouseDown() => trayManager.popUpContextMenu();

  @override
  void onTrayMenuItemClick(MenuItem menuItem) {
    switch (menuItem.key) {
      case 'show':
        _showWindow();
      case 'play':
        _provider.togglePlayPause();
      case 'next':
        _provider.skipToNext();
      case 'previous':
        _provider.skipToPrevious();
      case 'quit':
        _quit();
    }
  }

  @override
  void onWindowClose() => windowManager.hide();

  Future<void> _quit() async {
    await trayManager.destroy();
    await windowManager.setPreventClose(false);
    await windowManager.destroy();
  }
}
