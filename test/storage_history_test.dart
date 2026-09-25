import 'dart:io';

import 'package:flutter/material.dart' show ThemeMode;
import 'package:flutter_test/flutter_test.dart';
import 'package:hive_ce/hive.dart';
import 'package:music_player/models/media_item_model.dart';
import 'package:music_player/services/storage_service.dart';

AppMediaItem _track(String id) => AppMediaItem(
      id: id,
      title: 'Track $id',
      artist: 'Artist',
      sourceType: MediaSourceType.local,
    );

void main() {
  late Directory dir;
  final storage = StorageService();

  setUp(() async {
    dir = await Directory.systemTemp.createTemp('pulse_hive_');
    Hive.init(dir.path);
    await Hive.openBox<String>(StorageService.historyBox);
    await Hive.openBox<String>(StorageService.settingsBox);
  });

  tearDown(() async {
    await Hive.deleteFromDisk();
    await dir.delete(recursive: true);
  });

  // Hive sorts keys, so ids that sort opposite to play order catch any
  // reliance on key order.
  test('history is most recent first, not ordered by id', () async {
    for (final id in ['c', 'b', 'a']) {
      await storage.addToHistory(_track(id));
      await Future<void>.delayed(const Duration(milliseconds: 2));
    }
    expect(storage.getHistory().map((t) => t.id), ['a', 'b', 'c']);

    await storage.addToHistory(_track('c'));
    expect(storage.getHistory().map((t) => t.id), ['c', 'a', 'b']);
  });

  test('trimming drops the oldest plays', () async {
    for (var i = 0; i < StorageService.historyLimit + 3; i++) {
      // Zero-padded descending ids: the oldest plays sort *last* by key.
      final id = (1000 - i).toString().padLeft(4, '0');
      await storage.addToHistory(_track(id));
      await Future<void>.delayed(const Duration(milliseconds: 1));
    }
    final ids = storage.getHistory().map((t) => t.id).toList();
    expect(ids.length, StorageService.historyLimit);
    expect(ids, isNot(contains('1000')));
    expect(ids.first, (1000 - StorageService.historyLimit - 2).toString().padLeft(4, '0'));
  });

  test('clearHistory empties it and historyCount follows', () async {
    await storage.addToHistory(_track('a'));
    await storage.addToHistory(_track('b'));
    expect(storage.historyCount, 2);
    await storage.clearHistory();
    expect(storage.historyCount, 0);
    expect(storage.getHistory(), isEmpty);
  });

  group('settings', () {
    test('home language defaults to Tamil and can be turned off', () async {
      expect(storage.getHomeLanguage(), StorageService.defaultHomeLanguage);
      await storage.setHomeLanguage('Hindi');
      expect(storage.getHomeLanguage(), 'Hindi');
      await storage.setHomeLanguage(null);
      expect(storage.getHomeLanguage(), isNull);
    });

    test('theme defaults to dark, icon to light; both round-trip', () async {
      expect(storage.getThemeMode(), ThemeMode.dark);
      expect(storage.getDarkLauncherIcon(), isFalse);
      await storage.setThemeMode(ThemeMode.system);
      await storage.setDarkLauncherIcon(true);
      expect(storage.getThemeMode(), ThemeMode.system);
      expect(storage.getDarkLauncherIcon(), isTrue);
    });

    test('audio quality defaults to balanced and round-trips', () async {
      expect(storage.getAudioQuality(), AudioQuality.balanced);
      await storage.setAudioQuality(AudioQuality.dataSaver);
      expect(storage.getAudioQuality(), AudioQuality.dataSaver);
    });

    test('recent searches: newest first, no repeats, capped', () async {
      await storage.addRecentSearch('leo song');
      await storage.addRecentSearch('  Anirudh ');
      await storage.addRecentSearch('LEO SONG');
      await storage.addRecentSearch('   ');
      expect(storage.getRecentSearches(), ['LEO SONG', 'Anirudh']);

      for (var i = 0; i < StorageService.recentSearchLimit + 5; i++) {
        await storage.addRecentSearch('q$i');
      }
      final recent = storage.getRecentSearches();
      expect(recent.length, StorageService.recentSearchLimit);
      expect(recent.first, 'q${StorageService.recentSearchLimit + 4}');

      await storage.clearRecentSearches();
      expect(storage.getRecentSearches(), isEmpty);
    });
  });
}
