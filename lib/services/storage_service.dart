import 'dart:convert';
import 'package:flutter/material.dart' show ThemeMode, debugPrint;
import 'package:hive_ce_flutter/hive_flutter.dart';
import '../models/home_sections.dart';
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
  // Caches: losing them only costs speed, so they are safe to clear.
  static const String streamUrlsBox = 'stream_urls';
  static const String searchCacheBox = 'search_cache';
  static const String playbackLogBox = 'playback_log';
  static const String customDownloadPathKey = 'custom_download_path';
  static const String homeLanguageKey = 'home_language';
  static const String audioQualityKey = 'audio_quality';
  static const String recentSearchesKey = 'recent_searches';
  static const String themeModeKey = 'theme_mode';
  static const String dataSaverOnMobileKey = 'data_saver_on_mobile';
  static const String homeLayoutKey = 'home_layout';
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
    await Hive.openBox<String>(streamUrlsBox);
    await Hive.openBox<String>(searchCacheBox);
    await Hive.openBox<String>(playbackLogBox);
  }

  /// A cache box, or null where it isn't open (tests that only set up the
  /// boxes they need). Callers treat null as "no cache".
  static Box<String>? cacheBox(String name) =>
      Hive.isBoxOpen(name) ? Hive.box<String>(name) : null;

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

  /// The user's home page arrangement (order, hidden, added sections).
  HomeLayout getHomeLayout() {
    final raw = _settingsBox.get(homeLayoutKey);
    if (raw == null) return HomeLayout.standard;
    try {
      return HomeLayout.fromJson(jsonDecode(raw));
    } catch (_) {
      return HomeLayout.standard;
    }
  }

  Future<void> setHomeLayout(HomeLayout layout) =>
      _settingsBox.put(homeLayoutKey, jsonEncode(layout.toJson()));

  /// On mobile data, stream at Data saver quality whatever the chosen
  /// quality — about a third of the bytes, so songs start sooner on a weak
  /// signal. On by default.
  bool getDataSaverOnMobile() =>
      _settingsBox.get(dataSaverOnMobileKey) != 'false';

  Future<void> setDataSaverOnMobile(bool on) =>
      _settingsBox.put(dataSaverOnMobileKey, '$on');

  static const String autoplayKey = 'autoplay';
  static const String equalizerKey = 'equalizer';
  static const String updateCheckedKey = 'update_checked';

  /// True at most once a day: time for the quiet update check.
  Future<bool> updateCheckDue() async {
    final last = int.tryParse(_settingsBox.get(updateCheckedKey) ?? '') ?? 0;
    final now = DateTime.now().millisecondsSinceEpoch;
    if (now - last < const Duration(days: 1).inMilliseconds) return false;
    await _settingsBox.put(updateCheckedKey, '$now');
    return true;
  }

  /// Settings > Backup: favorites, playlists, history, settings and podcast
  /// positions as one JSON-able map. Downloads are left out — their files
  /// are on this phone only — and so are the caches.
  Map<String, dynamic> exportBackup() => {
        'app': 'pulse',
        'version': 1,
        'exportedAt': DateTime.now().toIso8601String(),
        for (final name in _backedUp) name: Map.of(Hive.box<String>(name).toMap()),
        positionsBox: Map.of(_posBox.toMap()),
      };

  static const _backedUp = [favoritesBox, playlistsBox, historyBox, settingsBox];

  /// Merge a backup into what's here (nothing is deleted). Returns how many
  /// entries were restored; throws [FormatException] if it isn't a Pulse
  /// backup.
  Future<int> importBackup(Map<String, dynamic> backup) async {
    if (backup['app'] != 'pulse') {
      throw const FormatException('Not a Pulse backup');
    }
    var count = 0;
    for (final name in _backedUp) {
      final entries = backup[name];
      if (entries is! Map) continue;
      final valid = {
        for (final e in entries.entries)
          if (e.value is String) '${e.key}': e.value as String,
      };
      await Hive.box<String>(name).putAll(valid);
      count += valid.length;
    }
    final positions = backup[positionsBox];
    if (positions is Map) {
      final valid = {
        for (final e in positions.entries)
          if (e.value is int) '${e.key}': e.value as int,
      };
      await _posBox.putAll(valid);
      count += valid.length;
    }
    return count;
  }

  /// Playback speed chosen for one podcast show; null until chosen.
  double? getPodcastSpeed(String show) =>
      double.tryParse(_settingsBox.get('podcast_speed:$show') ?? '');

  Future<void> setPodcastSpeed(String show, double speed) =>
      _settingsBox.put('podcast_speed:$show', '$speed');

  EqSettings getEqualizer() {
    try {
      return EqSettings.fromJson(jsonDecode(_settingsBox.get(equalizerKey)!));
    } catch (_) {
      return const EqSettings();
    }
  }

  Future<void> setEqualizer(EqSettings eq) =>
      _settingsBox.put(equalizerKey, jsonEncode(eq.toJson()));

  /// A yes/no setting stored as 'true'/'false'; [fallback] until set.
  bool getFlag(String key, {required bool fallback}) =>
      switch (_settingsBox.get(key)) {
        'true' => true,
        'false' => false,
        _ => fallback,
      };

  Future<void> setFlag(String key, bool on) => _settingsBox.put(key, '$on');

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

  /// History with how often each song was played, newest first.
  List<HistoryEntry> getHistoryEntries() {
    final entries = <HistoryEntry>[];
    for (final str in _histBox.values) {
      try {
        final json = jsonDecode(str) as Map<String, dynamic>;
        entries.add((
          item: AppMediaItem.fromJson(json),
          plays: (json['plays'] as int?) ?? 1,
          playedAt: (json['playedAt'] as int?) ?? 0,
        ));
      } catch (_) {}
    }
    entries.sort((a, b) => b.playedAt.compareTo(a.playedAt));
    return entries;
  }

  Future<void> addToHistory(AppMediaItem item) async {
    // Counted per song, for Stats and the "Made for you" rows.
    var plays = 0;
    try {
      final old = _histBox.get(item.id);
      if (old != null) plays = (jsonDecode(old)['plays'] as int?) ?? 1;
    } catch (_) {}
    await _histBox.put(
      item.id,
      jsonEncode({
        ...item.toJson(),
        'playedAt': DateTime.now().millisecondsSinceEpoch,
        'plays': plays + 1,
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

/// Settings > Equalizer: on/off, a gain per band (dB, in the phone's band
/// order), and extra loudness (dB).
class EqSettings {
  final bool enabled;
  final List<double> gains;
  final double loudness;

  const EqSettings({
    this.enabled = false,
    this.gains = const [],
    this.loudness = 0,
  });

  EqSettings copyWith({bool? enabled, List<double>? gains, double? loudness}) =>
      EqSettings(
        enabled: enabled ?? this.enabled,
        gains: gains ?? this.gains,
        loudness: loudness ?? this.loudness,
      );

  Map<String, dynamic> toJson() =>
      {'enabled': enabled, 'gains': gains, 'loudness': loudness};

  factory EqSettings.fromJson(Map<String, dynamic> json) => EqSettings(
        enabled: json['enabled'] == true,
        gains: [
          for (final g in (json['gains'] as List? ?? const []))
            (g as num).toDouble(),
        ],
        loudness: (json['loudness'] as num? ?? 0).toDouble(),
      );
}

typedef HistoryEntry = ({AppMediaItem item, int plays, int playedAt});
