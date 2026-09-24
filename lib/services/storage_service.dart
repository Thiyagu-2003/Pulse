import 'dart:convert';
import 'package:flutter/material.dart' show ThemeMode, debugPrint;
import 'package:hive_flutter/hive_flutter.dart';
import '../models/media_item_model.dart';
import '../models/playlist.dart';

/// Which YouTube audio stream to play. Downloads always keep AAC in MP4,
/// which is the safest thing to leave on disk.
enum AudioQuality {
  /// Lowest bitrate stream, around 50 kbps.
  dataSaver('Data saver', 'About 50 kbps — least mobile data'),

  /// AAC, about 128 kbps.
  balanced('Balanced', 'About 128 kbps'),

  /// Highest bitrate on offer, usually Opus at about 160 kbps.
  best('Best available', 'Up to 160 kbps');

  const AudioQuality(this.label, this.detail);
  final String label;
  final String detail;
}

class StorageService {
  static const String favoritesBox = 'favorites';
  static const String historyBox = 'history';
  static const String playlistsBox = 'playlists';
  static const String positionsBox = 'positions';
  static const String downloadsBox = 'downloads';
  static const String settingsBox = 'settings';
  static const String customDownloadPathKey = 'custom_download_path';
  static const String homeLanguageKey = 'home_language';
  static const String audioQualityKey = 'audio_quality';
  static const String recentSearchesKey = 'recent_searches';
  static const String themeModeKey = 'theme_mode';
  static const String darkLauncherIconKey = 'dark_launcher_icon';
  static const String defaultHomeLanguage = 'Tamil';
  static const int recentSearchLimit = 10;
  static const int historyLimit = 200;

  Future<void> init() async {
    await Hive.initFlutter();
    await Hive.openBox<String>(favoritesBox);
    await Hive.openBox<String>(historyBox);
    await Hive.openBox<String>(playlistsBox);
    await Hive.openBox<int>(positionsBox);
    await Hive.openBox<String>(downloadsBox);
    await Hive.openBox<String>(settingsBox);
  }

  /// Settings
  Box<String> get _settingsBox => Hive.box<String>(settingsBox);

  String? getCustomDownloadPath() => _settingsBox.get(customDownloadPathKey);

  Future<void> setCustomDownloadPath(String? path) async {
    if (path == null || path.isEmpty) {
      await _settingsBox.delete(customDownloadPathKey);
    } else {
      await _settingsBox.put(customDownloadPathKey, path);
    }
  }

  /// Home page language; null means no language rows. Stored as '' for null
  /// so "none" survives distinct from "never chosen".
  String? getHomeLanguage() {
    final stored = _settingsBox.get(homeLanguageKey);
    if (stored == null) return defaultHomeLanguage;
    return stored.isEmpty ? null : stored;
  }

  Future<void> setHomeLanguage(String? language) =>
      _settingsBox.put(homeLanguageKey, language ?? '');

  AudioQuality getAudioQuality() => AudioQuality.values.firstWhere(
        (q) => q.name == _settingsBox.get(audioQualityKey),
        orElse: () => AudioQuality.balanced,
      );

  Future<void> setAudioQuality(AudioQuality quality) =>
      _settingsBox.put(audioQualityKey, quality.name);

  /// Dark unless chosen otherwise — the app was designed dark first.
  ThemeMode getThemeMode() => ThemeMode.values.firstWhere(
        (m) => m.name == _settingsBox.get(themeModeKey),
        orElse: () => ThemeMode.dark,
      );

  Future<void> setThemeMode(ThemeMode mode) =>
      _settingsBox.put(themeModeKey, mode.name);

  /// The launcher shows the light icon (logo on white) unless chosen.
  bool getDarkLauncherIcon() => _settingsBox.get(darkLauncherIconKey) == 'true';

  Future<void> setDarkLauncherIcon(bool dark) =>
      _settingsBox.put(darkLauncherIconKey, '$dark');

  List<String> getRecentSearches() {
    final stored = _settingsBox.get(recentSearchesKey);
    if (stored == null) return [];
    try {
      return (jsonDecode(stored) as List).cast<String>();
    } catch (_) {
      return [];
    }
  }

  /// Most recent first, no repeats (ignoring case), capped.
  Future<void> addRecentSearch(String query) async {
    final q = query.trim();
    if (q.isEmpty) return;
    final recent = [
      q,
      ...getRecentSearches().where((s) => s.toLowerCase() != q.toLowerCase()),
    ].take(recentSearchLimit).toList();
    await _settingsBox.put(recentSearchesKey, jsonEncode(recent));
  }

  Future<void> clearRecentSearches() => _settingsBox.delete(recentSearchesKey);

  /// Downloads — kept separate from favorites. They answer different
  /// questions ("do I like this" vs "is this on disk") and downloads own a
  /// file that has to be deleted with them.
  Box<String> get _downloadBox => Hive.box<String>(downloadsBox);

  List<AppMediaItem> getDownloads() => _decodeAll(_downloadBox);

  bool isDownloaded(String id) => _downloadBox.containsKey(id);

  /// The on-disk copy of a track, if there is one.
  AppMediaItem? getDownload(String id) {
    final str = _downloadBox.get(id);
    if (str == null) return null;
    try {
      return AppMediaItem.fromJson(jsonDecode(str) as Map<String, dynamic>);
    } catch (e) {
      debugPrint('Skipping corrupt download entry $id: $e');
      return null;
    }
  }

  Future<void> saveDownload(AppMediaItem item) =>
      _downloadBox.put(item.id, jsonEncode(item.toJson()));

  Future<void> deleteDownload(String id) => _downloadBox.delete(id);

  /// Playlists Management
  Box<String> get _playlistBox => Hive.box<String>(playlistsBox);

  List<Playlist> getPlaylists() {
    final playlists = <Playlist>[];
    for (final str in _playlistBox.values) {
      try {
        playlists.add(Playlist.fromJson(jsonDecode(str) as Map<String, dynamic>));
      } catch (e) {
        debugPrint('Skipping corrupt playlist: $e');
      }
    }
    return playlists;
  }

  Playlist? getPlaylist(String id) {
    final str = _playlistBox.get(id);
    if (str == null) return null;
    try {
      return Playlist.fromJson(jsonDecode(str) as Map<String, dynamic>);
    } catch (e) {
      debugPrint('Skipping corrupt playlist $id: $e');
      return null;
    }
  }

  Future<void> savePlaylist(Playlist playlist) =>
      _playlistBox.put(playlist.id, jsonEncode(playlist.toJson()));

  Future<void> deletePlaylist(String id) => _playlistBox.delete(id);

  /// Resume Positions (milliseconds, keyed by track id)
  Box<int> get _posBox => Hive.box<int>(positionsBox);

  Duration? getPosition(String id) {
    final ms = _posBox.get(id);
    return ms == null ? null : Duration(milliseconds: ms);
  }

  Future<void> savePosition(String id, Duration position) =>
      _posBox.put(id, position.inMilliseconds);

  Future<void> clearPosition(String id) => _posBox.delete(id);

  /// Favorites Management
  Box<String> get _favBox => Hive.box<String>(favoritesBox);

  List<AppMediaItem> getFavorites() => _decodeAll(_favBox);

  bool isFavorite(String id) => _favBox.containsKey(id);

  Future<void> toggleFavorite(AppMediaItem item) async {
    if (isFavorite(item.id)) {
      await _favBox.delete(item.id);
    } else {
      await saveFavorite(item);
    }
  }

  /// Unconditionally store/replace a favorite (used by downloads, which must
  /// not un-favorite an already-favorited track).
  Future<void> saveFavorite(AppMediaItem item) async {
    await _favBox.put(item.id, jsonEncode(item.toJson()));
  }

  /// History Management
  Box<String> get _histBox => Hive.box<String>(historyBox);

  /// Most recent first. Hive keeps keys *sorted*, not in insertion order, so
  /// recency has to be stored in the entry itself; entries written before
  /// that carry no stamp and sort last.
  List<AppMediaItem> getHistory() {
    final entries = <(int, AppMediaItem)>[];
    for (final str in _histBox.values) {
      try {
        final json = jsonDecode(str) as Map<String, dynamic>;
        entries.add(((json['playedAt'] as int?) ?? 0, AppMediaItem.fromJson(json)));
      } catch (e) {
        debugPrint('Skipping corrupt history entry: $e');
      }
    }
    entries.sort((a, b) => b.$1.compareTo(a.$1));
    return [for (final e in entries) e.$2];
  }

  int get historyCount => _histBox.length;

  Future<void> clearHistory() => _histBox.clear();

  Future<void> addToHistory(AppMediaItem item) async {
    await _histBox.put(
      item.id,
      jsonEncode({
        ...item.toJson(),
        'playedAt': DateTime.now().millisecondsSinceEpoch,
      }),
    );

    // Keep history bounded by dropping the oldest plays.
    if (_histBox.length > historyLimit) {
      final keep = getHistory().take(historyLimit).map((t) => t.id).toSet();
      await _histBox.deleteAll(
        _histBox.keys.where((k) => !keep.contains(k)).toList(),
      );
    }
  }

  /// Skips entries that fail to decode (e.g. written by an older schema)
  /// rather than taking down the whole Library screen.
  List<AppMediaItem> _decodeAll(Box<String> box) {
    final items = <AppMediaItem>[];
    for (final str in box.values) {
      try {
        items.add(AppMediaItem.fromJson(jsonDecode(str) as Map<String, dynamic>));
      } catch (e) {
        debugPrint('Skipping corrupt stored item: $e');
      }
    }
    return items;
  }
}
