// Windows specifics: the Local tab reads the Music folder, and data from
// older builds moves out of Documents.
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:music_player/models/media_item_model.dart';
import 'package:music_player/services/local_music_service.dart';
import 'package:music_player/services/storage_service.dart';

void main() {
  final sep = Platform.pathSeparator;

  test('the Music folder scan finds audio, skips Pulse downloads', () async {
    final music = await Directory.systemTemp.createTemp('pulse_music_');
    Future<void> touch(String rel) async {
      final f = File('${music.path}$sep$rel');
      await f.parent.create(recursive: true);
      await f.writeAsString('x');
    }

    await touch('Anirudh - Hukum.mp3');
    await touch('Albums${sep}Leo${sep}Badass.FLAC');
    await touch('cover.jpg');
    await touch('Pulse${sep}Vaseegara - Bombay Jayashri [abc].m4a');

    final songs = await LocalMusicService.scanFolder(music);
    expect(songs.map((s) => s.title), ['Badass', 'Hukum']);
    final hukum = songs.last;
    expect(hukum.artist, 'Anirudh');
    expect(hukum.streamUrl, endsWith('Hukum.mp3'));
    expect(hukum.sourceType, MediaSourceType.local);
    expect(songs.first.album, 'Leo');
    expect(RegExp(r'^\d+$').hasMatch(hukum.id), isTrue);

    expect(await LocalMusicService.scanFolder(Directory('${music.path}${sep}nope')),
        isEmpty);
    await music.delete(recursive: true);
  });

  test('boxes left in Documents move once, never overwriting', () async {
    final docs = await Directory.systemTemp.createTemp('pulse_docs_');
    final data = await Directory.systemTemp.createTemp('pulse_data_');
    await File('${docs.path}${sep}favorites.hive').writeAsString('old favs');
    await File('${docs.path}${sep}favorites.lock').writeAsString('');
    await File('${docs.path}${sep}settings.hive').writeAsString('old settings');
    await File('${data.path}${sep}settings.hive').writeAsString('current');

    // Without Pulse's own caches beside them, they could be another app's.
    await StorageService.moveBoxes(docs, data);
    expect(File('${data.path}${sep}favorites.hive').existsSync(), isFalse);

    await File('${docs.path}${sep}stream_urls.hive').writeAsString('');
    await File('${docs.path}${sep}playback_log.hive').writeAsString('');
    await StorageService.moveBoxes(docs, data);

    expect(await File('${data.path}${sep}favorites.hive').readAsString(),
        'old favs');
    expect(File('${docs.path}${sep}favorites.hive').existsSync(), isFalse);
    expect(File('${docs.path}${sep}favorites.lock').existsSync(), isFalse);
    // Already there: left alone on both sides.
    expect(await File('${data.path}${sep}settings.hive').readAsString(),
        'current');
    expect(File('${docs.path}${sep}settings.hive').existsSync(), isTrue);
    await docs.delete(recursive: true);
    await data.delete(recursive: true);
  });
}
