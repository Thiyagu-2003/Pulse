import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive_ce/hive.dart';
import 'package:music_player/models/media_item_model.dart';
import 'package:music_player/providers/music_player_provider.dart';
import 'package:music_player/services/audio_handler.dart';
import 'package:music_player/services/storage_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tempDir;
  late StorageService storageService;
  late MusicPlayerProvider provider;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('pulse_conflict_test_');
    Hive.init(tempDir.path);
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
    storageService = StorageService();
    provider = MusicPlayerProvider(CustomAudioHandler(), storageService);
  });

  tearDown(() async {
    await Hive.close();
    try {
      if (tempDir.existsSync()) {
        await tempDir.delete(recursive: true);
      }
    } catch (_) {}
  });

  group('MusicPlayerProvider conflict resolution', () {
    final track1 = AppMediaItem(
      id: 't-1',
      title: 'First Song',
      artist: 'Artist A',
      sourceType: MediaSourceType.saavn,
    );
    final track2 = AppMediaItem(
      id: 't-2',
      title: 'Second Song',
      artist: 'Artist B',
      sourceType: MediaSourceType.saavn,
    );
    final track3 = AppMediaItem(
      id: 't-3',
      title: 'Third Song',
      artist: 'Artist C',
      sourceType: MediaSourceType.saavn,
    );

    test('hasPlaylistNamed matches case-insensitively', () async {
      await provider.createPlaylist('Chill Beats');
      expect(provider.hasPlaylistNamed('Chill Beats'), isTrue);
      expect(provider.hasPlaylistNamed('chill beats'), isTrue);
      expect(provider.hasPlaylistNamed('  CHILL BEATS  '), isTrue);
      expect(provider.hasPlaylistNamed('Workout'), isFalse);
    });

    test('import with keepBoth auto-renames duplicates with (1), (2)', () async {
      await provider.createPlaylist('Favorites');
      final imported1 = await provider.importPlaylistWithResolution(
        name: 'Favorites',
        items: [track1],
        resolution: PlaylistConflictResolution.keepBoth,
      );
      expect(imported1.name, 'Favorites (1)');
      expect(imported1.items.length, 1);

      final imported2 = await provider.importPlaylistWithResolution(
        name: 'Favorites',
        items: [track2],
        resolution: PlaylistConflictResolution.keepBoth,
      );
      expect(imported2.name, 'Favorites (2)');
      expect(imported2.items.length, 1);
    });

    test('import with replace overwrites items and resets folder', () async {
      final original = await provider.createPlaylist('Driving');
      await provider.addToPlaylist(original.id, track1);
      // Pretend it had a folder set from download
      await storageService.savePlaylist(
        original.copyWith(items: [track1], folder: 'Driving_Folder'),
      );

      final replaced = await provider.importPlaylistWithResolution(
        name: 'Driving',
        items: [track2, track3],
        resolution: PlaylistConflictResolution.replace,
      );

      expect(replaced.id, original.id);
      expect(replaced.name, 'Driving');
      expect(replaced.folder, isNull);
      expect(replaced.items.map((t) => t.id).toList(), ['t-2', 't-3']);
    });

    test('import with merge appends non-duplicate tracks', () async {
      final original = await provider.createPlaylist('Study');
      await provider.addToPlaylist(original.id, track1);

      // Merge with track1 (duplicate id) and track2 (new)
      final merged = await provider.importPlaylistWithResolution(
        name: 'Study',
        items: [track1, track2],
        resolution: PlaylistConflictResolution.merge,
      );

      expect(merged.id, original.id);
      expect(merged.items.length, 2);
      expect(merged.items.map((t) => t.id).toList(), ['t-1', 't-2']);
    });
  });
}
