import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hive_ce/hive.dart';
import 'package:music_player/models/media_item_model.dart';
import 'package:music_player/models/playlist.dart';
import 'package:music_player/services/storage_service.dart';

void main() {
  final storage = StorageService();
  final song = AppMediaItem(
      id: 's1', title: 'Song', artist: 'A', sourceType: MediaSourceType.saavn);

  setUp(() async {
    Hive.init((await Directory.systemTemp.createTemp('pulse_backup_')).path);
    for (final box in [
      StorageService.favoritesBox,
      StorageService.historyBox,
      StorageService.playlistsBox,
      StorageService.downloadsBox,
      StorageService.settingsBox,
    ]) {
      await Hive.openBox<String>(box);
    }
    await Hive.openBox<int>(StorageService.positionsBox);
  });

  tearDown(() => Hive.close());

  test('a backup restores favorites, playlists, history, settings, positions',
      () async {
    await storage.toggleFavorite(song);
    await storage.savePlaylist(Playlist(id: 'p1', name: 'Mine', items: [song]));
    await storage.addToHistory(song);
    await storage.setFlag(StorageService.autoplayKey, false);
    await storage.savePosition('ep', const Duration(minutes: 3));
    await storage.saveDownload(song); // not backed up
    // Through JSON, as it goes to and from the file.
    final file = jsonDecode(jsonEncode(storage.exportBackup()));

    for (final box in [
      StorageService.favoritesBox,
      StorageService.historyBox,
      StorageService.playlistsBox,
      StorageService.downloadsBox,
      StorageService.settingsBox,
    ]) {
      await Hive.box<String>(box).clear();
    }
    await Hive.box<int>(StorageService.positionsBox).clear();

    expect(await storage.importBackup(file), greaterThanOrEqualTo(5));
    expect(storage.isFavorite('s1'), isTrue);
    expect(storage.getPlaylist('p1')!.items.single.id, 's1');
    expect(storage.getHistory().single.id, 's1');
    expect(storage.getFlag(StorageService.autoplayKey, fallback: true), isFalse);
    expect(storage.getPosition('ep'), const Duration(minutes: 3));
    expect(storage.isDownloaded('s1'), isFalse);
  });

  test('anything else is refused', () async {
    expect(() => storage.importBackup({'boxes': {}}), throwsFormatException);
  });
}
