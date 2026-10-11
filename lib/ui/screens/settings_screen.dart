import 'dart:io';
import 'dart:convert';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../models/home_sections.dart';
import '../../providers/music_player_provider.dart';
import '../../services/storage_service.dart';
import '../../services/playback_cache.dart';
import '../../services/platform_bridge.dart';
import '../../services/update_service.dart';
import '../../services/voice_command_service.dart';
import '../theme/app_theme.dart';
import '../widgets/download_folder.dart';
import 'customize_home_screen.dart';
import 'diagnostics_screen.dart';
import 'equalizer_screen.dart';
import 'stats_screen.dart';

class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key});

  static Future<void> _backUp(
    BuildContext context,
    MusicPlayerProvider provider,
  ) async {
    final messenger = ScaffoldMessenger.of(context);
    final day = DateTime.now().toIso8601String().substring(0, 10);
    try {
      final saved = await FilePicker.saveFile(
        dialogTitle: 'Save backup',
        fileName: 'pulse-backup-$day.json',
        mimeType: 'application/json',
        bytes: utf8.encode(jsonEncode(provider.exportBackup())),
      );
      if (saved != null) {
        messenger.showSnackBar(const SnackBar(content: Text('Backup saved')));
      }
    } catch (e) {
      messenger.showSnackBar(SnackBar(content: Text('Backup failed: $e')));
    }
  }

  static Future<void> _restore(
    BuildContext context,
    MusicPlayerProvider provider,
  ) async {
    final messenger = ScaffoldMessenger.of(context);
    try {
      final picked = await FilePicker.pickFiles(
        dialogTitle: 'Choose a Pulse backup',
        type: FileType.custom,
        allowedExtensions: const ['json'],
      );
      if (picked.isEmpty) return;
      final backup = jsonDecode(await picked.first.xFile.readAsString());
      final count = await provider.restoreBackup(
        backup as Map<String, dynamic>,
      );
      messenger.showSnackBar(
        SnackBar(content: Text('Restored $count items from the backup')),
      );
    } catch (e) {
      messenger.showSnackBar(
        const SnackBar(content: Text("That file isn't a Pulse backup")),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<MusicPlayerProvider>();
    final quality = provider.audioQuality;
    final language = provider.homeLanguage;
    final historyCount = provider.historyCount;

    return Scaffold(
      appBar: AppBar(title: const Text('Settings')),
      body: ListView(
        children: [
          const _Heading('Appearance'),
          ListTile(
            leading: const Icon(Icons.dark_mode_outlined),
            title: const Text('Theme'),
            subtitle: Text(_themeLabel(provider.themeMode)),
            onTap: () => _pick<ThemeMode>(
              context,
              options: const [
                ThemeMode.system,
                ThemeMode.light,
                ThemeMode.dark,
              ],
              selected: provider.themeMode,
              label: _themeLabel,
              onPicked: provider.setThemeMode,
            ),
          ),
          ListTile(
            leading: ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: Image.asset(
                provider.darkLauncherIcon
                    ? 'icons/app_icon_dark.png'
                    : 'icons/app_icon_light.png',
                width: 32,
                height: 32,
              ),
            ),
            title: const Text('App icon'),
            subtitle: Text(
              '${provider.darkLauncherIcon ? 'Dark' : 'Light'} · widget and '
              'notifications change now, the home-screen icon when you '
              'leave the app',
            ),
            onTap: () => _pick<bool>(
              context,
              options: const [false, true],
              selected: provider.darkLauncherIcon,
              label: (dark) => dark ? 'Dark' : 'Light',
              onPicked: provider.setDarkLauncherIcon,
            ),
          ),
          ListTile(
            leading: const Icon(Icons.widgets_rounded),
            title: const Text('Home screen widgets'),
            subtitle: const Text(
              'Add a Now Playing widget to your device home screen',
            ),
            onTap: () => _showWidgetsSheet(context),
          ),
          ListTile(
            leading: const Icon(Icons.tune_rounded),
            title: const Text('Customize home'),
            subtitle: const Text(
              'Order, hide or add sections on the Online page',
            ),
            onTap: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const CustomizeHomeScreen()),
            ),
          ),
          const _Heading('Playback'),
          ListTile(
            leading: const Icon(Icons.high_quality_rounded),
            title: const Text('Audio quality'),
            subtitle: Text('${quality.label} · ${quality.detail}'),
            onTap: () => _pick<AudioQuality>(
              context,
              options: AudioQuality.values,
              selected: quality,
              label: (q) => q.label,
              onPicked: provider.setAudioQuality,
            ),
          ),
          ListTile(
            leading: const Icon(Icons.translate_rounded),
            title: const Text('Home language'),
            subtitle: Text(
              language == null
                  ? 'No language rows on the home screen'
                  : '$language rows on the home screen',
            ),
            onTap: () => _pick<String?>(
              context,
              options: [...homeLanguages, null],
              selected: language,
              label: (l) => l ?? 'No language rows',
              onPicked: provider.setHomeLanguage,
            ),
          ),
          ListTile(
            leading: const Icon(Icons.equalizer_rounded),
            title: const Text('Equalizer'),
            subtitle: Text(
              provider.equalizerSettings.enabled
                  ? 'On'
                  : 'Off · bass boost, vocal, treble, loudness',
            ),
            onTap: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const EqualizerScreen()),
            ),
          ),
          SwitchListTile(
            secondary: const Icon(Icons.all_inclusive_rounded),
            title: const Text('Autoplay'),
            subtitle: const Text(
              'When the queue ends, keep playing similar songs',
            ),
            value: provider.autoplay,
            onChanged: provider.setAutoplay,
          ),
          SwitchListTile(
            secondary: const Icon(Icons.signal_cellular_alt_rounded),
            title: const Text('Data saver on mobile data'),
            subtitle: const Text(
              'Lower quality on mobile data, so songs start sooner',
            ),
            value: provider.dataSaverOnMobile,
            onChanged: provider.setDataSaverOnMobile,
          ),
          SwitchListTile(
            secondary: const Icon(Icons.stop_circle_outlined),
            title: const Text('Stop playback on app close'),
            subtitle: const Text(
              'Stop music when Pulse is closed from recent apps instead of continuing in the background',
            ),
            value: provider.stopPlaybackOnClose,
            onChanged: provider.setStopPlaybackOnClose,
          ),
          SwitchListTile(
            secondary: const Icon(Icons.notifications_active_outlined),
            title: const Text('Playback notification'),
            subtitle: const Text(
              'Show media controls and track info in the notification panel',
            ),
            value: provider.playbackNotificationEnabled,
            onChanged: provider.setPlaybackNotificationEnabled,
          ),
          if (VoiceCommandService.isSupported)
            SwitchListTile(
              secondary: const Icon(Icons.mic_none_rounded),
              title: const Text('Hands-free voice control'),
              subtitle: const Text(
                'Show floating mic button on the home screen to control music and search by voice',
              ),
              value: provider.voiceControlEnabled,
              onChanged: (on) => provider.setVoiceControlEnabled(on, context),
            ),
          // Releases carry Android APKs; the check can't read a desktop
          // build's version, and would always say "latest".
          if (Platform.isAndroid)
            ListTile(
              leading: const Icon(Icons.system_update_rounded),
              title: const Text('Check for updates'),
              subtitle: FutureBuilder<String?>(
                future: PlatformBridge.appVersion(),
                builder: (_, v) => Text('Pulse ${v.data ?? ''}'.trim()),
              ),
              onTap: () async {
                final messenger = ScaffoldMessenger.of(context);
                final update = await UpdateService.check();
                if (!context.mounted) return;
                if (update == null) {
                  messenger.showSnackBar(
                    const SnackBar(
                      content: Text("You're on the latest version"),
                    ),
                  );
                } else {
                  showUpdateDialog(context, update);
                }
              },
            ),
          ListTile(
            leading: const Icon(Icons.folder_open_rounded),
            title: const Text('Download folder'),
            subtitle: Text(downloadFolderLabel(provider)),
            trailing: provider.customDownloadPath == null
                ? null
                : TextButton(
                    onPressed: () => provider.setCustomDownloadPath(null),
                    child: const Text('Reset'),
                  ),
            onTap: () => chooseDownloadFolder(context),
          ),
          const _Heading('Library'),
          ListTile(
            leading: const Icon(Icons.backup_rounded),
            title: const Text('Back up'),
            subtitle: const Text(
              'Save favorites, playlists, history and settings to a file',
            ),
            onTap: () => _backUp(context, provider),
          ),
          ListTile(
            leading: const Icon(Icons.settings_backup_restore_rounded),
            title: const Text('Restore'),
            subtitle: const Text('Add everything from a backup file'),
            onTap: () => _restore(context, provider),
          ),
          ListTile(
            leading: const Icon(Icons.insights_rounded),
            title: const Text('Listening stats'),
            subtitle: const Text('Most played songs and artists'),
            onTap: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const StatsScreen()),
            ),
          ),
          ListTile(
            leading: const Icon(Icons.delete_sweep_rounded),
            title: const Text('Clear listening history'),
            subtitle: Text(
              historyCount == 1 ? '1 entry' : '$historyCount entries',
            ),
            enabled: historyCount > 0,
            onTap: () => _confirmClearHistory(context, provider),
          ),
          ListTile(
            leading: const Icon(Icons.cleaning_services_rounded),
            title: const Text('Clear stream cache'),
            subtitle: const Text('Use this if a song refuses to start'),
            onTap: () {
              provider.ytService
                ..clearStreamCache()
                ..clearSearchCache();
              ScaffoldMessenger.of(context)
                ..hideCurrentSnackBar()
                ..showSnackBar(
                  const SnackBar(
                    content: Text('Stream cache cleared'),
                    behavior: SnackBarBehavior.floating,
                  ),
                );
            },
          ),
          _SavedSongsTile(key: ValueKey(historyCount)),
          ListTile(
            leading: const Icon(Icons.monitor_heart_outlined),
            title: const Text('Diagnostics'),
            subtitle: const Text('How recent songs started, step by step'),
            onTap: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const DiagnosticsScreen()),
            ),
          ),
          const _Heading('About'),
          const ListTile(
            leading: Icon(Icons.info_outline_rounded),
            title: Text('Pulse'),
            subtitle: Text(
              'Your local music, online audio and podcasts in one player. '
              'No ads, no account.',
            ),
          ),
        ],
      ),
    );
  }

  static String _mb(int bytes) => '${(bytes / (1024 * 1024)).round()} MB';

  static String _themeLabel(ThemeMode mode) => switch (mode) {
    ThemeMode.system => 'Follow system',
    ThemeMode.light => 'Light',
    ThemeMode.dark => 'Dark',
  };

  /// A bottom sheet of options with the current one marked.
  void _pick<T>(
    BuildContext context, {
    required List<T> options,
    required T selected,
    required String Function(T) label,
    required Future<void> Function(T) onPicked,
  }) {
    showModalBottomSheet(
      context: context,
      backgroundColor: context.colors.surface,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (sheetContext) => SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(vertical: 8),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              for (final option in options)
                ListTile(
                  leading: Icon(
                    option == selected
                        ? Icons.radio_button_checked_rounded
                        : Icons.radio_button_off_rounded,
                    color: option == selected
                        ? context.colors.accent
                        : context.colors.mist.withValues(alpha: 0.6),
                  ),
                  title: Text(label(option)),
                  onTap: () {
                    Navigator.pop(sheetContext);
                    onPicked(option);
                  },
                ),
            ],
          ),
        ),
      ),
    );
  }

  void _showWidgetsSheet(BuildContext context) {
    final widgets = [
      (
        id: 'bar',
        name: 'Classic Bar',
        size: '4 × 1',
        desc: 'Horizontal music bar with album art and full playback controls.',
        icon: Icons.view_stream_rounded,
      ),
      (
        id: 'compact',
        name: 'Mini',
        size: '2 × 1',
        desc: 'Compact space-saving music widget with quick play/pause.',
        icon: Icons.crop_16_9_rounded,
      ),
      (
        id: 'square',
        name: 'Square',
        size: '2 × 2',
        desc: 'Modern square music card with prominent artwork and controls.',
        icon: Icons.crop_square_rounded,
      ),
      (
        id: 'card',
        name: 'Expanded Card',
        size: '4 × 2',
        desc: 'Large music card with prominent artwork and controls.',
        icon: Icons.calendar_view_day_rounded,
      ),
    ];

    showModalBottomSheet(
      context: context,
      backgroundColor: context.colors.surface,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (sheetContext) => SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Center(
                child: Container(
                  width: 36,
                  height: 4,
                  margin: const EdgeInsets.only(bottom: 16),
                  decoration: BoxDecoration(
                    color: context.colors.mist.withValues(alpha: 0.2),
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              const Text(
                'Home screen widgets',
                style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 6),
              Text(
                'Choose a widget style to add to your phone home screen, or long-press an empty space on your phone home screen and select Widgets > Pulse.',
                style: TextStyle(
                  fontSize: 13,
                  color: context.colors.mist.withValues(alpha: 0.7),
                ),
              ),
              const SizedBox(height: 16),
              for (final w in widgets)
                Container(
                  margin: const EdgeInsets.only(bottom: 12),
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: context.colors.mist.withValues(alpha: 0.04),
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(
                      color: context.colors.mist.withValues(alpha: 0.08),
                    ),
                  ),
                  child: Row(
                    children: [
                      Container(
                        width: 44,
                        height: 44,
                        decoration: BoxDecoration(
                          color: AppTheme.primary.withValues(alpha: 0.15),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Icon(w.icon, color: AppTheme.primary),
                      ),
                      const SizedBox(width: 14),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Text(
                                  w.name,
                                  style: const TextStyle(
                                    fontWeight: FontWeight.bold,
                                    fontSize: 15,
                                  ),
                                ),
                                const SizedBox(width: 8),
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 6,
                                    vertical: 2,
                                  ),
                                  decoration: BoxDecoration(
                                    color: context.colors.mist.withValues(alpha: 0.1),
                                    borderRadius: BorderRadius.circular(6),
                                  ),
                                  child: Text(
                                    w.size,
                                    style: TextStyle(
                                      fontSize: 11,
                                      fontWeight: FontWeight.w600,
                                      color: context.colors.mist.withValues(alpha: 0.8),
                                    ),
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 2),
                            Text(
                              w.desc,
                              style: TextStyle(
                                fontSize: 12,
                                color: context.colors.mist.withValues(alpha: 0.6),
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 8),
                      FilledButton.tonal(
                        style: FilledButton.styleFrom(
                          padding: const EdgeInsets.symmetric(horizontal: 14),
                          visualDensity: VisualDensity.compact,
                        ),
                        onPressed: () async {
                          Navigator.pop(sheetContext);
                          final supported = await PlatformBridge.isPinWidgetSupported();
                          if (supported) {
                            await PlatformBridge.pinWidget(w.id);
                          } else {
                            if (context.mounted) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(
                                  content: Text(
                                    'To add this widget: long-press on your phone\'s home screen, tap "Widgets", and select Pulse.',
                                  ),
                                  behavior: SnackBarBehavior.floating,
                                ),
                              );
                            }
                          }
                        },
                        child: const Text('Add'),
                      ),
                    ],
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _confirmClearHistory(
    BuildContext context,
    MusicPlayerProvider provider,
  ) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        backgroundColor: context.colors.surface,
        title: const Text('Clear listening history?'),
        content: const Text(
          'Recently played and the quick picks on the home screen start '
          'over. Favorites, playlists and downloads are kept.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('Clear'),
          ),
        ],
      ),
    );
    if (confirmed == true) await provider.clearHistory();
  }
}

class _Heading extends StatelessWidget {
  final String text;
  const _Heading(this.text);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 24, 20, 4),
      child: Text(
        text.toUpperCase(),
        style: TextStyle(
          fontSize: 12,
          letterSpacing: 1.5,
          fontWeight: FontWeight.bold,
          color: context.colors.accent,
        ),
      ),
    );
  }
}

/// Size of the instant-replay cache, with tap-to-clear. Re-measures after
/// clearing (and, via its key, after more songs are played).
class _SavedSongsTile extends StatefulWidget {
  const _SavedSongsTile({super.key});

  @override
  State<_SavedSongsTile> createState() => _SavedSongsTileState();
}

class _SavedSongsTileState extends State<_SavedSongsTile> {
  late Future<int> _size = PlaybackCache.instance.sizeBytes();

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<int>(
      future: _size,
      builder: (context, snapshot) => ListTile(
        leading: const Icon(Icons.offline_bolt_outlined),
        title: const Text('Saved songs for instant replay'),
        subtitle: Text(
          '${SettingsScreen._mb(snapshot.data ?? 0)} · up to '
          '${SettingsScreen._mb(PlaybackCache.maxBytes)}, oldest removed '
          'first. Tap to clear.',
        ),
        onTap: () async {
          await PlaybackCache.instance.clear();
          if (mounted) {
            setState(() => _size = PlaybackCache.instance.sizeBytes());
          }
        },
      ),
    );
  }
}

/// "Pulse 1.2.0 is available" with its release notes and a Download button
/// (opens the APK in the browser; Android then offers to install it).
void showUpdateDialog(BuildContext context, AppUpdate update) {
  showDialog<void>(
    context: context,
    builder: (dialogContext) => AlertDialog(
      title: Text('Pulse ${update.version} is available'),
      content: update.notes.isEmpty
          ? null
          : SingleChildScrollView(child: Text(update.notes)),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(dialogContext),
          child: const Text('Later'),
        ),
        TextButton(
          onPressed: () {
            Navigator.pop(dialogContext);
            PlatformBridge.openUrl(update.url);
          },
          child: const Text('Download'),
        ),
      ],
    ),
  );
}
