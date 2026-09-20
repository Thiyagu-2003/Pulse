import 'dart:convert';
import 'package:hive_flutter/hive_flutter.dart';
import '../models/media_item_model.dart';

class StorageService {
  static const String favoritesBox = 'favorites';
  static const String historyBox = 'history';
  static const String playlistsBox = 'playlists';

  Future<void> init() async {
    await Hive.initFlutter();
    await Hive.openBox<String>(favoritesBox);
    await Hive.openBox<String>(historyBox);
    await Hive.openBox<String>(playlistsBox);
  }

  /// Favorites Management
  Box<String> get _favBox => Hive.box<String>(favoritesBox);

  List<AppMediaItem> getFavorites() {
    return _favBox.values
        .map((str) => AppMediaItem.fromJson(jsonDecode(str)))
        .toList();
  }

  bool isFavorite(String id) => _favBox.containsKey(id);

  Future<void> toggleFavorite(AppMediaItem item) async {
    if (isFavorite(item.id)) {
      await _favBox.delete(item.id);
    } else {
      await _favBox.put(item.id, jsonEncode(item.toJson()));
    }
  }

  /// History Management
  Box<String> get _histBox => Hive.box<String>(historyBox);

  List<AppMediaItem> getHistory() {
    return _histBox.values
        .map((str) => AppMediaItem.fromJson(jsonDecode(str)))
        .toList()
        .reversed
        .toList();
  }

  Future<void> addToHistory(AppMediaItem item) async {
    await _histBox.put(item.id, jsonEncode(item.toJson()));
  }
}
