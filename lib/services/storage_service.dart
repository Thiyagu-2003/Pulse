import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:hive_flutter/hive_flutter.dart';
import '../models/media_item_model.dart';
import '../models/playlist.dart';

class StorageService {
  static const String favoritesBox = 'favorites';
  static const String historyBox = 'history';
  static const String playlistsBox = 'playlists';
  static const String positionsBox = 'positions';
  static const String downloadsBox = 'downloads';
  static const String settingsBox = 'settings';
  static const String customDownloadPathKey = 'custom_download_path';
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

  List<AppMediaItem> getHistory() => _decodeAll(_histBox).reversed.toList();

  Future<void> addToHistory(AppMediaItem item) async {
    // Re-putting an existing key keeps its original insertion position, so a
    // replayed track would never move to the top. Delete first.
    await _histBox.delete(item.id);
    await _histBox.put(item.id, jsonEncode(item.toJson()));

    // Keep history bounded; Hive keys are returned in insertion order.
    while (_histBox.length > historyLimit) {
      await _histBox.delete(_histBox.keyAt(0));
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
