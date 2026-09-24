import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../models/home_sections.dart';
import '../../providers/music_player_provider.dart';
import '../../services/storage_service.dart';
import '../theme/app_theme.dart';

class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key});

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
              options: const [ThemeMode.system, ThemeMode.light, ThemeMode.dark],
              selected: provider.themeMode,
              label: _themeLabel,
              onPicked: provider.setThemeMode,
            ),
          ),
          ListTile(
            leading: const Icon(Icons.apps_rounded),
            title: const Text('App icon'),
            subtitle: Text(
              '${provider.darkLauncherIcon ? 'Dark' : 'Light'} · '
              'changes on your home screen when you leave the app',
            ),
            onTap: () => _pick<bool>(
              context,
              options: const [false, true],
              selected: provider.darkLauncherIcon,
              label: (dark) => dark ? 'Dark' : 'Light',
              onPicked: provider.setDarkLauncherIcon,
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
          const _Heading('Library'),
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
